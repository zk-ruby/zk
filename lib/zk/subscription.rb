module ZK
  # Basic pattern for objects that have the concept of a parent (the thing that 
  # granted this subscription), a callback, and that can unregister (so the
  # callback no longer receives events). 
  #
  # expects the 'parent' to respond_to? the 'unregister' method, and will
  # be passed the subscription instance 
  module Subscription
    class Base
      include ZK::Logging

      # the object from which we will attempt to #unregister on
      # XXX: need a better name for this
      attr_reader :parent
      
      # the user-supplied callback block, used to create a ThreadedCallback
      attr_reader :callable

      def initialize(parent, block)
        raise ArgumentError, "block must repsond_to?(:call)" unless block.respond_to?(:call)
        @parent = parent
        @callable = block
        @mutex = Monitor.new
      end

      def unregister
        parent.unregister(self)
      end
      alias unsubscribe unregister

      # @private
      def call(*args)
        callable.call(*args)
      end

      protected
        def synchronize
          @mutex.synchronize { yield }
        end
    end

    module ActorStyle
      extend Concern

      included do
        alias_method_chain :unsubscribe, :threaded_callback
        alias_method_chain :callable, :threaded_callback_wrapper
      end

      def unsubscribe_with_threaded_callback
        synchronize do
          @threaded_callback.shutdown
          unsubscribe_without_threaded_callback
        end
      end
    
      def callable_with_threaded_callback_wrapper(*args)
        synchronize do 
          @threaded_callback ||= ThreadedCallback.new(@callable) 
        end
      end
    end
  end
end

