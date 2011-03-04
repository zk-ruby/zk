module ZK
  # this is the default watcher provided by the zookeeper connection
  # watchers are implemented by adding the :watch => true flag to
  # any #children or #get or #exists calls
  # you never really need to initialize this yourself
  class EventHandler
    include org.apache.zookeeper.Watcher if defined?(JRUBY_VERSION)
    include ZK::Logging

    #:stopdoc:

    OUTSTANDING_WATCH_TYPES = [:data, :child].freeze
    VALID_REGISTER_TYPES = (WATCH_SYM_TO_INT.keys + [:all]).freeze

    attr_accessor :zk

    #:startdoc:

    def initialize(zookeeper_client) #:nodoc:
      @zk = zookeeper_client
      @callbacks = Hash.new { |h,path| h[path] = Hash.new { |m,typ| m[typ] = [] } }

      @mutex = Monitor.new

      @outstanding_watches = OUTSTANDING_WATCH_TYPES.inject({}) do |h,k|
        h.tap { |x| x[k] = Set.new }
      end
    end

    # register a path with the handler
    # your block will be called with all events on that path.
    #
    # aliased as #subscribe
    #
    # opts:
    # * <tt>:events</tt>: either a Symbol or Array of Symbols indicating what
    #   type of event this callback should handle. If not given, the block
    #   will be called for all events. The valid types are: 
    #   <tt>[:created, :deleted, :changed, :child, :all]</tt>. :all is the
    #   default. The present tense variants <tt>[:create, :delete, :change]</tt> may
    #   also be used, as can <tt>:children</tt>
    #
    #
    # @param [String] path the path you want to listen to
    # @param [Block] block the block to execute when a watch event happpens
    #
    # @yield [connection, event] We will call your block with the connection the
    #   watch event occured on and the event object
    #
    # @return [ZooKeeper::EventHandlerSubscription] the subscription object
    #   you can use to to unsubscribe from an event
    #
    def register(path, opts={}, &block)
      types = extract_watch_types(opts)

      logger.debug { "EventHandler#register path=#{path.inspect} types=#{types.inspect}" }

      EventHandlerSubscription.new(self, path, block, types).tap do |subscription|
        synchronize do 
          types.each do |t|
            @callbacks[path][t] << subscription
          end
        end
      end
    end
    alias :subscribe :register

    # registers a "state of the connection" handler
    # @param [String] state the state you want to register for
    # @param [Block] block the block to execute on state changes
    # @yield [connection, event] yields your block with
    def register_state_handler(state, &block)
      register(state_key(state), :types => :session, &block)
    end

    # @deprecated use #unsubscribe on the subscription object
    # @see ZooKeeper::EventHandlerSubscription#unsubscribe
    def unregister_state_handler(*args)
      if args.first.is_a?(EventHandlerSubscription)
        unregister(args.first)
      else
        unregister(state_key(args.first), args[1])
      end
    end

    def unregister(subscription) #:nodoc:
      synchronize do
        subscription.types.each do |type|
          @callbacks[subscription.path][type].delete(subscription)
        end
      end

      nil
    end
    alias :unsubscribe :unregister

    # called from the client-registered callback when an event fires
    def process(event) #:nodoc:
      logger.debug { "EventHandler#process dispatching event: #{event.inspect}" } unless event.type == -1
      event.zk = @zk

      cb_key = 
        if event.node_event?
          event.path
        elsif event.state_event?
          state_key(event.state)
        else
          raise ZKError, "don't know how to process event: #{event.inspect}"
        end

      event_action = WATCH_INT_TO_SYM[event.type]

      cb_ary = synchronize do 
        if event.node_event?
          if watch_type = ZOOKEEPER_WATCH_TYPE_MAP[event.type] # this is :child or :data

            logger.debug { "re-allowing #{watch_type.inspect} watches on path #{event.path.inspect}" }
            
            # we recieved a watch event for this path, now we allow code to set new watchers
            @outstanding_watches[watch_type].delete(event.path)
          end
        end

        h = @callbacks[cb_key]

        h.fetch(event_action, h[:all]).dup
      end

      cb_ary.compact!

      safe_call(cb_ary, event)
    end

    # used during shutdown to clear registered listeners
    def clear! #:nodoc:
      synchronize do
        @callbacks.clear
        nil
      end
    end

    def synchronize #:nodoc:
      @mutex.synchronize { yield }
    end

    def get_default_watcher_block
      lambda do |hash|
        watcher_callback.tap do |cb|
          cb.call(hash)
        end
      end
    end

    # implements not only setting up the watcher callback, but deduplicating 
    # event delivery. Keeps track of in-flight watcher-type+path requests and
    # doesn't re-register the watcher with the server until a response has been
    # fired. This prevents one event delivery to *every* callback per :watch => true
    # argument.
    def setup_watcher!(watch_type, opts)
      return unless opts.delete(:watch)

      synchronize do
        set = @outstanding_watches.fetch(watch_type)
        path = opts[:path]

        if set.add?(path)
          # this path has no outstanding watchers, let it do its thing
          opts[:watcher] = watcher_callback 
        else
          # outstanding watch for path and data pair already exists, so ignore
          logger.debug { "outstanding watch request for path #{path.inspect} and watcher type #{watch_type.inspect}, not re-registering" }
        end
      end
    end

    protected
      def watcher_callback
        ZookeeperCallbacks::WatcherCallback.create { |event| process(event) }
      end

      unless defined?(EVENT_NAME_ALIASES)
        EVENT_NAME_ALIASES = Hash.new { |h,k| k }

        EVENT_NAME_ALIASES.merge!({
          :create   => :created,
          :delete   => :deleted,
          :children => :child,
          :change   => :changed,
        })
      end

      def extract_watch_types(opts)
        types = Array(opts[:events] || :all).map { |n| EVENT_NAME_ALIASES[n] }  # convert aliases to real event names

        invalid_args = (types - VALID_REGISTER_TYPES)
        raise ArgumentError, "Invalid register :type arguments: #{invalid_args.inspect}" unless invalid_args.empty?

        types
      end

      def state_key(arg)
        int = 
          case arg
          when String, Symbol
            ZookeeperConstants.const_get(:"ZOO_#{arg.to_s.upcase}_STATE")
          when Integer
            arg
          else
            raise NameError # ugh lame
          end

        "state_#{int}"
      rescue NameError
        raise ArgumentError, "#{arg} is not a valid zookeeper state"
      end

      def safe_call(callbacks, *args)
        callbacks.each do |cb|
          begin
            cb.call(*args) if cb.respond_to?(:call)
          rescue Exception => e
            logger.error { "Error caught in user supplied callback" }
            logger.error { e.to_std_format }
          end
        end
      end
  end
end

