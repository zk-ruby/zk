module ZK
  # the subscription object that is passed back from subscribing
  # to events.
  # @see ZK::Client::Base#register
  class EventHandlerSubscription
    # the event handler associated with this subscription
    # @return [EventHandler]
    attr_accessor :event_handler

    # the path this subscription is for
    # @return [String]
    attr_accessor :path
    
    # the block associated with the path
    # @return [Proc]
    attr_accessor :callback

    # @private
    def initialize(event_handler, path, callback)
      @event_handler, @path, @callback = event_handler, path, callback
    end

    # unsubscribe from the path or state you were watching
    # @see ZK::Client::Base#register
    def unsubscribe
      @event_handler.unregister(self)
    end
    alias :unregister :unsubscribe

    # @private
    def call(event)
      callback.call(event)
    end
  end
end

