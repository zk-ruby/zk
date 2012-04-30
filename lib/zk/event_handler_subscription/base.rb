module ZK
  module EventHandlerSubscription
    class Base
      # the event handler associated with this subscription
      # @return [EventHandler]
      attr_accessor :event_handler

      # the path this subscription is for
      # @return [String]
      attr_accessor :path
      
      # the block associated with the path
      # @return [Proc]
      attr_accessor :callback

      # an array of what kinds of events this handler is interested in receiving
      #
      # @return [Set] containing any combination of :create, :change, :delete,
      #   or :children
      #
      # @private
      attr_accessor :interests

      ALL_EVENTS    = [:created, :deleted, :changed, :child].freeze unless defined?(ALL_EVENTS)
      ALL_EVENT_SET = Set.new(ALL_EVENTS).freeze                    unless defined?(ALL_EVENT_SET)

      # @private
      def initialize(event_handler, path, callback, interests)
        @event_handler, @path, @callback = event_handler, path, callback
        @interests = prep_interests(interests)
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

      protected
        def prep_interests(a)
          return ALL_EVENT_SET if a.nil?

          rval = 
            case a
            when Array
              Set.new(a)
            when Symbol
              Set.new([a])
            else
              raise ArgumentError, "Don't know how to handle interests: #{a.inspect}" 
            end

          rval.tap do |rv|
            invalid = (rv - ALL_EVENT_SET)
            raise ArgumentError, "Invalid event name(s) #{invalid.to_a.inspect} given" unless invalid.empty?
          end
        end
    end # Base
  end # EventHandlerSubscription
end # ZK
