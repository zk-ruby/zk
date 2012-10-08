module ZK
  module Client
    # Provides client-state related methods. Included in ZK::Client::Base.
    # (refactored out to this class to ease documentation overload)
    module StateMixin
      # Register a block to be called when *any* connection event occurs
      #
      # @yield [event] yields the connection event to the block
      # @yieldparam event [ZK::Event] the event that occurred
      def on_state_change(&block)
        watcher.register_state_handler(:all, &block)
      end

      # Register a block to be called on connection, when the client has
      # connected. 
      # 
      # the block will be called with no arguments
      #
      # returns an EventHandlerSubscription object that can be used to unregister
      # this block from further updates
      #
      def on_connected(&block)
        watcher.register_state_handler(:connected, &block)
      end

      # register a block to be called when the client is attempting to reconnect
      # to the zookeeper server. the documentation says that this state should be
      # taken to mean that the application should enter into "safe mode" and operate
      # conservatively, as it won't be getting updates until it has reconnected
      #
      def on_connecting(&block)
        watcher.register_state_handler(:connecting, &block)
      end

      # register a block to be called when our session has expired. This
      # usually happens due to a network partitioning event, and means that all
      # watches must be re-registered with the server (i.e. after the
      # on_connected event is received). Callbacks set up via #register are
      # still valid and will respond to events, it's the event delivery you
      # have to set up again by using :watch.
      #
      # @todo need to come up with a way to test this
      def on_expired_session(&block)
        watcher.register_state_handler(:expired_session, &block)
      end

      private
        def wrap_state_closed_error
          yield
        rescue RuntimeError => e
          # gah, lame error parsing here
          raise e unless e.message == 'zookeeper handle is closed'
          false
        end
    end
  end
end

