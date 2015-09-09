module ZK
  # A class that encapsulates the queue + thread that calls a callback.
  # Repsonds to `call` but places call on a queue to be delivered by a thread.
  # You will not have a useful return value from `call` so this is only useful
  # for background processing.
  class ThreadedCallback
    include ZK::Logger
    include ZK::Exceptions

    attr_reader :callback

    def initialize(callback=nil, &blk)
      @callback = callback || blk

      @state  = :paused
      reopen_after_fork!
    end

    def running?
      @mutex.synchronize { @state == :running }
    end

    # @private
    def alive?
      @thread && @thread.alive?
    end

    # how long to wait on thread shutdown before we return
    def shutdown(timeout=5)
#       logger.debug { "#{self.class}##{__method__}" }

      @mutex.lock
      begin
        return true if @state == :shutdown

        @state = :shutdown
        @cond.broadcast
      ensure
        @mutex.unlock rescue nil
      end

      return true unless @thread 

      unless @thread.join(timeout) == @thread
        logger.error { "#{self.class} timed out waiting for dispatch thread, callback: #{callback.inspect}" }
        return false
      end

      true
    end

    def call(*args)
      @mutex.lock
      begin
        @array << args
        @cond.broadcast
      ensure
        @mutex.unlock rescue nil
      end
    end

    # called after a fork to replace a dead delivery thread
    # special case, there should be ONLY ONE THREAD RUNNING, 
    # (the one that survived the fork)
    #
    # @private
    def reopen_after_fork!
#       logger.debug { "#{self.class}##{__method__}" }

      unless @state == :paused
        raise InvalidStateError, "state should have been :paused, not: #{@state.inspect}"
      end

      if @thread 
        raise InvalidStateError, "WTF?! did you fork in a callback? my thread was alive!" if @thread.alive?
        @thread = nil
      end

      @mutex  = Mutex.new
      @cond   = ConditionVariable.new
      @array  = []
      resume_after_fork_in_parent
    end

    # shuts down the event delivery thread, but keeps the queue so we can continue
    # delivering queued events when {#resume_after_fork_in_parent} is called
    def pause_before_fork_in_parent
      @mutex.lock
      begin
        raise InvalidStateError, "@state was not :running, @state: #{@state.inspect}" if @state != :running
        return if @state == :paused 

        @state = :paused
        @cond.broadcast
      ensure
        @mutex.unlock rescue nil
      end

      return unless @thread

      @thread.join
      @thread = nil
    end

    def resume_after_fork_in_parent
      @mutex.lock
      begin
        raise InvalidStateError, "@state was not :paused, @state: #{@state.inspect}" if @state != :paused
        raise InvalidStateError, "@thread was not nil! #{@thread.inspect}" if @thread 

        @state = :running
#         logger.debug { "#{self.class}##{__method__} spawning dispatch thread" }
        spawn_dispatch_thread
      ensure
        @mutex.unlock rescue nil
      end
    end

    private
      # intentionally *not* synchronized
      def spawn_dispatch_thread
        @thread = Thread.new(&method(:dispatch_thread_body))
      end

      def dispatch_thread_body
        Thread.current.abort_on_exception = true
        Thread.current[:callback] = @callback
        while true
          args = nil

          @mutex.lock
          begin
            @cond.wait(@mutex) while @array.empty? and @state == :running

            if @state != :running
              logger.debug { "ThreadedCallback, state is #{@state.inspect}, returning" } 
              return 
            end

            args = @array.shift
          ensure
            @mutex.unlock rescue nil
          end
            
          begin
            callback.call(*args)
          rescue Exception => e
            logger.error { e.to_std_format }
          end
        end
      ensure
        Thread.current[:callback] = nil
        logger.debug { "##{__method__} returning" }
      end
  end
end

