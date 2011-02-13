module ZK
  # the subscription object that is passed back from subscribing
  # to events.
  # @see ZooKeeperEventHandler#subscribe
  class EventHandlerSubscription
    attr_accessor :event_handler, :path, :callback

    # @private
    # :nodoc:
    def initialize(event_handler, path, callback)
      @event_handler, @path, @callback = event_handler, path, callback
    end

    # unsubscribe from the path or state you were watching
    # @see ZooKeeperEventHandler#subscribe
    def unsubscribe
      @event_handler.unregister(self)
    end
    alias :unregister :unsubscribe

    # @private
    # :nodoc:
    def call(event)
      callback.call(event)
    end

  end
end

