module ZK
  # this is the default watcher provided by the zookeeper connection
  # watchers are implemented by adding the :watch => true flag to
  # any #children or #get or #exists calls
  # you never really need to initialize this yourself
  class EventHandler
    include org.apache.zookeeper.Watcher if defined?(JRUBY_VERSION)
    include ZK::Logging


    # @private
    # :nodoc:
    attr_accessor :zk

    # @private
    # :nodoc:
    def initialize(zookeeper_client)
      @zk = zookeeper_client
      @callbacks = Hash.new { |h,k| h[k] = [] }

      # allow for synchronization on shutdown
      @callbacks.extend(MonitorMixin)
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
        @callbacks[path] << subscription
      end
    end
    alias :subscribe :register

    # registers a "state of the connection" handler
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
        @callbacks[path][index] = nil
        return
      end
      ary = @callbacks[subscription.path]
      if index = ary.index(subscription)
        ary[index] = nil
      end
    end
    alias :unsubscribe :unregister

    # called from the client-registered callback when an event fires
    def process(event) #:nodoc:
      @callbacks.synchronize do
        logger.debug { "EventHandler#process dispatching event: #{event.inspect}" } unless event.type == -1
        event.zk = @zk

        if event.node_event?
          @callbacks[event.path].each do |callback|
            callback.call(event) if callback.respond_to?(:call)
          end
        elsif event.state_event?
          @callbacks[state_key(event.state)].each do |callback|
            callback.call(event) if callback.respond_to?(:call)
          end
        end
      end
    end

    # used during shutdown to clear registered listeners
    def clear! #:nodoc:
      @callbacks.synchronize do
        @callbacks.clear
        nil
      end
    end

    protected
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
  end
end

