module ZK
  module EventHandlerSubscription
    # Stealing some ideas from Celluloid, this event handler subscription
    # (basically, the wrapper around the user block), will spin up its own
    # thread for delivery, and use a queue. This gives us the basis for better
    # concurrency (event handlers run in parallel), but preserves the
    # underlying behavior that a single-event-thread ZK gives us, which is that
    # a single callback block is inherently serial. Without this, you have to
    # make sure your callbacks are either synchronized, or totally reentrant,
    # so that multiple threads could be calling your block safely (which is
    # really difficult, and annoying).
    #
    # Using this delivery mechanism means that the block still must not block
    # forever, however each event will "wait its turn" and all callbacks will
    # receive their events in the same order (which is what ZooKeeper
    # guarantees), just perhaps at different times.
    #
    class Actor < Base
      # @private
      attr_reader :threaded_callback

      def initialize(parent, path, callback, opts={})
        super
        @threaded_callback = ThreadedCallback.new(@callable)
      end

      def async?
        true
      end

      def call(*args)
        @threaded_callback.call(*args)
      end
      
      # calls unsubscribe and shuts down 
      def close
        unregister
      end

      def unregister
        super
        @threaded_callback.shutdown
      end

      def reopen_after_fork!
        logger.debug { "#{self.class}##{__method__}" }
        super
        @threaded_callback.reopen_after_fork!
      end

      def pause_before_fork_in_parent
        synchronize do
          logger.debug { "#{self.class}##{__method__}" }
          @threaded_callback.pause_before_fork_in_parent
          super
        end
      end

      def resume_after_fork_in_parent
        super
        logger.debug { "#{self.class}##{__method__}" }
        @threaded_callback.resume_after_fork_in_parent
      end
    end
  end
end
