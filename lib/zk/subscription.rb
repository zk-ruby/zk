module ZK
  # Base class for objects that have the concept of a parent (the thing that 
  # granted this subscription), a callback, and that can unregister (so the
  # callback no longer receives events). 
  #
  # expects the 'parent' to respond_to? the 'unregister' method, and will
  # be passed this instance
  class Subscription
    include ZK::Logging

    attr_reader :parent, :callable

    def initialize(parent, block)
      raise ArgumentError, "block must repsond_to?(:call)" unless block.respond_to?(:call)
      @parent = parent
      @callable = block
      @threaded_callback = ThreadedCallback.new(block)
    end

    def unregister
      @threaded_callback.shutdown
      parent.unregister(self)
    end
    alias unsubscribe unregister

    # @private
    def call(*args)
      @threaded_callback.call(*args)
    end
  end
end

