module ZK
  # Basic pattern for objects that have the concept of a parent (the thing that 
  # granted this subscription), a callback, and that can unregister (so the
  # callback no longer receives events). 
  #
  # expects the 'parent' to respond_to? the 'unregister' method, and will
  # be passed the subscription instance 
  module Subscription
    class Base
      include ZK::Logger

      # the object from which we will attempt to #unregister on
      # XXX: need a better name for this
      attr_reader :parent
      
      # the user-supplied callback block, used to create a ThreadedCallback
      attr_reader :callable

      def initialize(parent, block)
        raise ArgumentError, "block must repsond_to?(:call)" unless block.respond_to?(:call)
        raise ArgumentError, "parent must respond_to?(:unregister)" unless parent.respond_to?(:unregister)
        @parent   = parent
        @callable = block
        @mutex    = Monitor.new
      end

      def unregistered?
        @parent.nil?
      end

      # calls unregister on parent, then sets parent to nil
      def unregister
        obj = nil

        synchronize do
          return false unless @parent
          obj, @parent = @parent, nil
        end

        obj.unregister(self)
      end

      # an alias for unregister
      def unsubscribe
        unregister
      end

      # @private
      def call(*args)
        callable.call(*args)
      end

      # @private
      def reopen_after_fork!
        @mutex = Monitor.new
      end

      private
        def synchronize
          @mutex.synchronize { yield }
        end
    end
  end
end

