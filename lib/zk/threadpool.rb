module ZK
  # a simple threadpool for running blocks of code off the main thread
  class Threadpool
    include Logger
    include Exceptions

    DEFAULT_SIZE = 5

    class << self
      # size of the ZK.defer threadpool (defaults to 5)
      attr_accessor :default_size
      ZK::Threadpool.default_size = DEFAULT_SIZE
    end

    # the size of this threadpool
    attr_reader :size

    def initialize(size=nil)
      @size = size || self.class.default_size

      @threadpool = []
      @state = :new
      @queue = []

      @mutex = Mutex.new
      @cond  = ConditionVariable.new

      @error_callbacks = []

      start!
    end

    # are all of our threads alive?
    # returns false if there are no running threads
    def alive?
      @mutex.lock
      begin
        !@threadpool.empty? and @threadpool.all?(&:alive?)
      ensure
        @mutex.unlock rescue nil
      end
    end

    # Queue an operation to be run on an internal threadpool. You may either
    # provide an object that responds_to?(:call) or pass a block. There is no
    # mechanism for retrieving the result of the operation, it is purely
    # fire-and-forget, so the user is expected to make arrangements for this in
    # their code. 
    #
    def defer(callable=nil, &blk)
      callable ||= blk

      raise ArgumentError, "Argument to Threadpool#defer must respond_to?(:call)" unless callable.respond_to?(:call)

      @mutex.lock
      begin
        @queue << callable
        @cond.broadcast
      ensure
        @mutex.unlock rescue nil
      end

      nil
    end

    def running?
      @mutex.lock
      begin
        @state == :running
      ensure
        @mutex.unlock rescue nil
      end
    end

    # returns true if the current thread is one of the threadpool threads
    def on_threadpool?
      tp = nil

      @mutex.synchronize do
        return false unless @threadpool # you can't dup nil
        tp = @threadpool.dup
      end

      tp.respond_to?(:include?) and tp.include?(Thread.current)
    end

    # starts the threadpool if not already running
    def start!
      @mutex.synchronize do
        return false if @state == :running
        @state = :running
        spawn_threadpool
      end

      true
    end

    # like the start! method, but checks for dead threads in the threadpool
    # (which will happen after a fork())
    #
    # This will reset the state of the pool and any blocks registered will be
    # lost
    #
    #
    # @private
    def reopen_after_fork!
      # ok, we know that only the child process calls this, right?
      return false unless (@state == :running) or (@state == :paused)
      logger.debug { "#{self.class}##{__method__}" }

      @state = :running
      @mutex = Mutex.new
      @cond  = ConditionVariable.new
      @queue = []
      prune_dead_threads
      spawn_threadpool
    end

    # @private
    def pause_before_fork_in_parent
      threads = nil

      @mutex.lock
      begin
        raise InvalidStateError, "invalid state, expected to be :running, was #{@state.inspect}" if @state != :running
        return false if @state == :paused
        threads = @threadpool.slice!(0, @threadpool.length)
        @state = :paused
        @cond.broadcast   # wake threads, let them die
      ensure
        @mutex.unlock rescue nil
      end

      join_all(threads)
      true
    end

    # @private
    def resume_after_fork_in_parent
      @mutex.lock
      begin
        raise InvalidStateError, "expected :paused, was #{@state.inspect}" if @state != :paused
      ensure
        @mutex.unlock rescue nil
      end

      start!
    end

    # register a block to be called back with unhandled exceptions that occur
    # in the threadpool. 
    # 
    # @note if your exception callback block itself raises an exception, I will
    #   make fun of you.
    #
    def on_exception(&blk)
      @mutex.synchronize do
        @error_callbacks << blk
      end
    end

    # join all threads in this threadpool, they will be given a maximum of +timeout+
    # seconds to exit before they are considered hung and will be ignored (this is an
    # issue with threads in general: see 
    # http://blog.headius.com/2008/02/rubys-threadraise-threadkill-timeoutrb.html for more info)
    #
    # the default timeout is 2 seconds per thread
    # 
    def shutdown(timeout=2)
      threads = nil

      @mutex.lock
      begin
        return false if @state == :shutdown
        @state = :shutdown

        @queue.clear
        threads, @threadpool = @threadpool, []
        @cond.broadcast
      ensure
        @mutex.unlock rescue nil
      end

      join_all(threads)

      nil
    end

    private
      def join_all(threads, timeout=nil)
        while th = threads.shift
          begin
            th.join(timeout)
          rescue Exception => e
            logger.error { "Caught exception shutting down threadpool" }
            logger.error { e.to_std_format }
          end
        end
      end
      
      def dispatch_to_error_handler(e)
        # make a copy that will be free from thread manipulation
        # and doesn't require holding the lock
        cbs = @mutex.synchronize { @error_callbacks.dup }

        if cbs.empty?
          default_exception_handler(e)
        else
          while cb = cbs.shift
            begin
              cb.call(e)
            rescue Exception => e
              msg = [ 
                "Exception caught in user supplied on_exception handler.", 
                "Just meditate on the irony of that for a moment. There. Good.",
                "The callback that errored was: #{cb.inspect}, the exception was",
                ""
              ]

              default_exception_handler(e, msg.join("\n"))
            end
          end
        end
      end

      def default_exception_handler(e, msg=nil)
        msg ||= 'Exception caught in threadpool'
        logger.error { "#{msg}: #{e.to_std_format}" }
      end

      def prune_dead_threads
        @mutex.lock
        begin
          threads, @threadpool = @threadpool, []
          return if threads.empty?

          while th = threads.shift
            begin
              if th.join(0).nil?
                @threadpool << th
              end
            rescue Exception => e
              logger.error { "Caught exception pruning threads in the threadpool" }
              logger.error { e.to_std_format }
            end
          end
        ensure
          @mutex.unlock rescue nil
        end
      end

      def spawn_threadpool
        until @threadpool.size >= @size.to_i
          @threadpool << Thread.new(&method(:worker_thread_body))
        end
#         logger.debug { "spawn threadpool complete" }
      end

      def worker_thread_body
        while true
          op = nil

          @mutex.lock
          begin
            return if @state != :running

            unless op = @queue.shift
              @cond.wait(@mutex) if @queue.empty? and (@state == :running)
            end
          ensure
            @mutex.unlock rescue nil
          end

          next unless op

#           logger.debug { "got #{op.inspect} in thread" }

          begin
            op.call if op
          rescue Exception => e
            dispatch_to_error_handler(e)
          end
        end
      end
  end
end

