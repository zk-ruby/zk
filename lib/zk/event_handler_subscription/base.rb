module ZK
  module EventHandlerSubscription
    class Base
      include ZK::Logging

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
      # this is the :only option, essentially
      #
      # @return [Set] containing any combination of :create, :change, :delete,
      #   or :children
      #
      # @private
      attr_accessor :interests

      ALL_EVENTS    = [:created, :deleted, :changed, :child].freeze unless defined?(ALL_EVENTS)
      ALL_EVENT_SET = Set.new(ALL_EVENTS).freeze                    unless defined?(ALL_EVENT_SET)

      # @private
      def initialize(event_handler, path, callback, opts={})
        @event_handler, @path, @callback = event_handler, path, callback
        @interests = prep_interests(opts[:only])
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

      # the Actor returns true for this
      # @private
      def async?
        false
      end

      protected
        def prep_interests(a)
          logger.debug { "prep_interests: #{a.inspect}" }
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
