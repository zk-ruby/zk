module ZK
  class NodeDeletionWatcher
    include Zookeeper::Constants
    include Exceptions
    include Logging

    # @private
    module Constants
      NOT_YET     = :not_yet
      BLOCKED     = :yes
      NOT_ANYMORE = :not_anymore
      INTERRUPTED = :interrupted
      TIMED_OUT   = :timed_out
    end
    include Constants

    attr_reader :zk, :path

    def initialize(zk, path)
      @zk     = zk
      @path   = path.dup

      @subs   = []

      @mutex  = Monitor.new # ffs, 1.8.7 compatibility w/ timeouts
      @cond   = @mutex.new_cond

      @blocked  = NOT_YET
      @result   = nil
    end

    def done?
      @mutex.synchronize { !!@result }
    end

    def blocked?
      @mutex.synchronize { @blocked == BLOCKED }
    end

    def timed_out?
      @mutex.synchronize { @result == TIMED_OUT }
    end

    # this is for testing, allows us to wait until this object has gone into
    # blocking state.
    #
    # avoids the race where if we have already been blocked and released
    # this will not block the caller
    #
    # pass optional timeout to return after that amount of time or nil to block
    # forever
    #
    # @return [true] if we have been blocked previously or are currently blocked,
    # @return [nil] if we timeout
    #
    def wait_until_blocked(timeout=nil)
      @mutex.synchronize do
        return true unless @blocked == NOT_YET

        start = Time.now
        time_to_stop = timeout ? (start + timeout) : nil

        logger.debug { "#{__method__} @blocked: #{@blocked.inspect} about to wait" } 
        @cond.wait(timeout)

        if (time_to_stop and (Time.now > time_to_stop)) and (@blocked == NOT_YET)
          return nil
        end

        (@blocked == NOT_YET) ? nil : true
      end
    end

    # cause a thread blocked by us to be awakened and have a WakeUpException
    # raised. 
    #
    # if a result has already been delivered, then this does nothing
    #
    # if a result has not *yet* been delivered, any thread calling
    # block_until_deleted will receive the exception immediately
    #
    def interrupt!
      @mutex.synchronize do
        case @blocked
        when NOT_YET, BLOCKED
          @result = INTERRUPTED
          @cond.broadcast
        else
          return
        end
      end
    end

    # @option opts [Numeric] :timeout (nil) if a positive integer, represents a duration in
    #   seconds after which, if we have not acquired the lock, a LockWaitTimeoutError will
    #   be raised in all waiting threads
    #
    def block_until_deleted(opts={})
      timeout = opts[:timeout]

      @mutex.synchronize do
        raise InvalidStateError, "Already fired for #{path}" if @result
        register_callbacks

        unless zk.exists?(path, :watch => true)
          # we are done, these are one-shot, so write the results
          @result = :deleted
          @blocked = NOT_ANYMORE
          @cond.broadcast # wake any waiting threads
          return true
        end

        logger.debug { "ok, going to block: #{path}" }

        @blocked = BLOCKED
        @cond.broadcast                 # wake threads waiting for @blocked to change

        wait_for_result(timeout)

        @blocked = NOT_ANYMORE

        logger.debug { "got result for path: #{path}, result: #{@result.inspect}" } 

        case @result
        when :deleted
          logger.debug { "path #{path} was deleted" }
          return true
        when TIMED_OUT
          raise ZK::Exceptions::LockWaitTimeoutError
        when INTERRUPTED
          raise ZK::Exceptions::WakeUpException
        when ZOO_EXPIRED_SESSION_STATE
          raise Zookeeper::Exceptions::SessionExpired
        when ZOO_CONNECTING_STATE
          raise Zookeeper::Exceptions::NotConnected
        when ZOO_CLOSED_STATE
          raise Zookeeper::Exceptions::ConnectionClosed
        else
          raise "Hit unexpected case in block_until_node_deleted, result was: #{@result.inspect}"
        end
      end
    ensure
      unregister_callbacks
    end

    private
      # this method must be synchronized on @mutex, obviously
      def wait_for_result(timeout)
        # do the deadline maths
        time_to_stop = timeout ? (Time.now + timeout) : nil # slight time slippage between here

        until @result
          if timeout                                        # and here
            now = Time.now

            if (now > time_to_stop)
              @result ||= TIMED_OUT # don't overwrite the @result
              return
            elsif @result
              return
            end

            @cond.wait(time_to_stop.to_f - now.to_f)
          else
            @cond.wait_until { @result }
          end
        end
      end

      def unregister_callbacks
        @subs.each(&:unregister)
      end

      def register_callbacks
        @subs << zk.register(path, &method(:node_deletion_cb))

        [:expired_session, :connecting, :closed].each do |sym|
          @subs << zk.event_handler.register_state_handler(sym, &method(:session_cb))
        end
      end

      def node_deletion_cb(event)
        @mutex.synchronize do
          if event.node_deleted?
            @result ||= :deleted
            @cond.broadcast
          else
            unless zk.exists?(path, :watch => true)
              @result ||= :deleted
              @cond.broadcast
            end
          end
        end
      end

      def session_cb(event)
        @mutex.synchronize do
          unless @result
            @result = event.state
            @cond.broadcast
          end
        end
      end
  end
end

