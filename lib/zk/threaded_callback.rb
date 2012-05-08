module ZK
  # A class that encapsulates the queue + thread that calls a callback.
  # Repsonds to `call` but places call on a queue to be delivered by a thread.
  # You will not have a useful return value from `call` so this is only useful
  # for background processing.
  class ThreadedCallback
    include ZK::Logging

    attr_reader :callback

    def initialize(callback=nil, &blk)
      @callback = callback || blk
      @mutex = Monitor.new

      @mutex.synchronize do
        @running = true
        reopen_after_fork!
      end
    end

    def running?
      @mutex.synchronize { @running }
    end

    # how long to wait on thread shutdown before we return
    def shutdown(timeout=2)
      @mutex.synchronize do
        @running = false
        @queue.push(KILL_TOKEN)
        return unless @thread 
        unless @thread.join(2)
          logger.error { "#{self.class} timed out waiting for dispatch thread, callback: #{callback.inspect}" }
        end
      end
    end

    def call(*args)
      @queue.push(args)
    end

    # called after a fork to replace a dead delivery thread
    # special case, there should be ONLY ONE THREAD RUNNING, 
    # (the one that survived the fork)
    #
    # @private
    def reopen_after_fork!
      return unless @running
      return if @thread and @thread.alive?
      @mutex = Monitor.new
      @queue = @queue ? @queue.zk_clone_after_fork : Queue.new
      @thread = spawn_dispatch_thread()
    end

    protected
      def spawn_dispatch_thread
        Thread.new do
          while running?
            args = @queue.pop
            break if args == KILL_TOKEN
            begin
              callback.call(*args)
            rescue Exception => e
              logger.error { "error caught in handler for path: #{path.inspect}, interests: #{interests.inspect}" }
              logger.error { e.to_std_format }
            end
          end
        end
      end
  end
end

