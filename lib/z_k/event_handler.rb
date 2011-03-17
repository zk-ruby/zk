module ZK
  # this is the default watcher provided by the zookeeper connection
  # watchers are implemented by adding the :watch => true flag to
  # any #children or #get or #exists calls
  # you never really need to initialize this yourself
  class EventHandler
    include org.apache.zookeeper.Watcher if defined?(JRUBY_VERSION)
    include ZK::Logging

    VALID_WATCH_TYPES = [:data, :child].freeze

    ZOOKEEPER_WATCH_TYPE_MAP = {
      Zookeeper::ZOO_CREATED_EVENT => :data,
      Zookeeper::ZOO_DELETED_EVENT => :data,
      Zookeeper::ZOO_CHANGED_EVENT => :data,
      Zookeeper::ZOO_CHILD_EVENT   => :child,
    }.freeze

    attr_accessor :zk  # :nodoc:

    # @private
    # :nodoc:
    def initialize(zookeeper_client)
      @zk = zookeeper_client
      @callbacks = Hash.new { |h,k| h[k] = [] }

      @mutex = Monitor.new

      @outstanding_watches = VALID_WATCH_TYPES.inject({}) do |h,k|
        h.tap { |x| x[k] = Set.new }
      end
    end

    # register a path with the handler
    # your block will be called with all events on that path.
    # aliased as #subscribe
    # @param [String] path the path you want to listen to
    # @param [Block] block the block to execute when a watch event happpens
    # @yield [connection, event] We will call your block with the connection the
    #   watch event occured on and the event object
    # @return [ZooKeeper::EventHandlerSubscription] the subscription object
    #   you can use to to unsubscribe from an event
    # @see ZooKeeper::WatcherEvent
    # @see ZooKeeper::EventHandlerSubscription
    def register(path, &block)
      logger.debug { "EventHandler#register path=#{path.inspect}" }
      EventHandlerSubscription.new(self, path, block).tap do |subscription|
        synchronize { @callbacks[path] << subscription }
      end
    end
    alias :subscribe :register

    # registers a "state of the connection" handler
    #
    # @param [String] state the state you want to register for
    # @param [Block] block the block to execute on state changes
    # @yield [connection, event] yields your block with
    def register_state_handler(state, &block)
      register(state_key(state), &block)
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

    # @deprecated use #unsubscribe on the subscription object
    # @see ZooKeeper::EventHandlerSubscription#unsubscribe
    def unregister(*args)
      if args.first.is_a?(EventHandlerSubscription)
        subscription = args.first
      elsif args.first.is_a?(String) and args[1].is_a?(EventHandlerSubscription)
        subscription = args[1]
      else
        path, index = args[0..1]
        synchronize { @callbacks[path][index] = nil }
        return
      end

      synchronize do
        ary = @callbacks[subscription.path]

        idx = ary.index(subscription) and ary.delete_at(idx)
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

      cb_ary = synchronize do 
        if event.node_event?
          if watch_type = ZOOKEEPER_WATCH_TYPE_MAP[event.type]
            logger.debug { "re-allowing #{watch_type.inspect} watches on path #{event.path.inspect}" }
            
            # we recieved a watch event for this path, now we allow code to set new watchers
            @outstanding_watches[watch_type].delete(event.path)
          end
        end

        @callbacks[cb_key].dup
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
      @default_watcher_block ||= lambda do |hash|
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
        raise ArgumentError, "#{arg} is not a valid zookeeper state", caller
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

