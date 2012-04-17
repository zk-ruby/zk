module ZK
  module Client
    # A simple threadsafe way of having a thread deliver a single value
    # to another thread. 
    #
    # Each thread making requests will have a thread-local continuation
    # that can be accessed via DropBox.current and one can use
    # DropBox.with_current that will clear the result once the given block
    # exits (allowing for reuse)
    #
    # (this class is in no way related to dropbox.com or Dropbox Inc.)
    class DropBox
      UNDEFINED = Object.new unless defined?(UNDEFINED)

      THREAD_LOCAL_KEY = :__zk_client_continuation_current__ unless defined?(THREAD_LOCAL_KEY)

      # @private
      attr_reader :value

      # sets the thread-local instance to nil, used by tests
      # @private
      def self.remove_current
        Thread.current[THREAD_LOCAL_KEY] = nil
      end

      # access the thread-local DropBox instance for the current thread
      def self.current
        Thread.current[THREAD_LOCAL_KEY] ||= self.new()
      end

      # yields the current thread's DropBox instance and clears its value
      # after the block returns
      def self.with_current
        yield current
      ensure
        current.clear
      end

      def initialize
        @mutex = Mutex.new
        @cond = ConditionVariable.new
        @value = UNDEFINED  # allows us to return nil
      end

      def push(obj)
        @mutex.synchronize do
          @value = obj
          @cond.signal
        end
      end

      def pop
        @mutex.synchronize do
          @cond.wait(@mutex)
          @value
        end
      end

      def clear
        @mutex.synchronize do
          @value = UNDEFINED
        end
      end

      # we are done if value is defined, use clear to reset
      def done?
        @value != UNDEFINED
      end
    end
  end
end

