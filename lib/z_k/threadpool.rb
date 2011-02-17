module ZK
  # a simple threadpool for running blocks of code off the main thread
  class Threadpool
    include Logging

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
      @threadqueue = ::Queue.new

      @mutex = Mutex.new

      start!
    end

    # Queue an operation to be run on an internal threadpool. You may either
    # provide an object that responds_to?(:call) or pass a block. There is no
    # mechanism for retrieving the result of the operation, it is purely
    # fire-and-forget, so the user is expected to make arrangements for this in
    # their code. 
    #
    def defer(callable=nil, &blk)
      callable ||= blk

      # XXX(slyphon): do we care if the threadpool is not running?
      raise Exceptions::ThreadpoolIsNotRunningException unless running?
      raise ArgumentError, "Argument to Threadpool#defer must respond_to?(:call)" unless callable.respond_to?(:call)

      @threadqueue << callable
      nil
    end

    def running?
      @mutex.synchronize { @running }
    end

    # starts the threadpool if not already running
    def start!
      @mutex.synchronize do
        return false if @running
        @running = true
        spawn_threadpool
      end
      true
    end

    # join all threads in this threadpool, they will be given a maximum of +timeout+
    # seconds to exit before they are considered hung and will be ignored (this is an
    # issue with threads in general: see 
    # http://blog.headius.com/2008/02/rubys-threadraise-threadkill-timeoutrb.html for more info)
    #
    # the default timeout is 2 seconds per thread
    # 
    def shutdown(timeout=2)
      @mutex.synchronize do
        return unless @running

        @running = false

        @threadqueue.clear
        @size.times { @threadqueue << KILL_TOKEN }

        while th = @threadpool.shift
          begin
            th.join(timeout)
          rescue Exception => e
            logger.error { "Caught exception shutting down threadpool" }
            logger.error { e.to_std_format }
          end
        end
      end

      nil
    end

    private
      def spawn_threadpool #:nodoc:
        until @threadpool.size == @size.to_i
          thread = Thread.new do
            while @running
              begin
                op = @threadqueue.pop
                break if op == KILL_TOKEN
                op.call
              rescue Exception => e
                logger.error { "Exception caught in threadpool" }
                logger.error { e.to_std_format }
              end
            end
          end

          @threadpool << thread
        end
      end
  end
end

