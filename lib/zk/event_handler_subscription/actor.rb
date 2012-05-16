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
      include Subscription::ActorStyle

      def async?
        true
      end

      # calls unsubscribe and shuts down 
      def close
        unsubscribe
      end

      def pause_before_fork_in_parent
        threaded_callback && threaded_callback.pause_before_fork_in_parent
      end

      def resume_after_fork_in_parent
        threaded_callback && threaded_callback.resume_after_fork_in_parent
      end
    end
  end
end
