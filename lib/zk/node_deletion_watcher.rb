module ZK
  class NodeDeletionWatcher
    include Zookeeper::Constants
    include Logger

    # @private
    module Constants
      NOT_YET     = :not_yet
      BLOCKED     = :yes
      NOT_ANYMORE = :not_anymore
      INTERRUPTED = :interrupted
      TIMED_OUT   = :timed_out
    end
    include Constants

    attr_reader :zk,
                :paths,
                :options,
                :watched_paths,
                :remaining_paths,
                :threshold

    # Create a new NodeDeletionWatcher that has the ability to block until
    # some or all of the paths given to it have been deleted.
    #
    # @param [ZK::client] zk
    #
    # @param [Array] paths - one or more paths to watch
    #
    # @param optional [Hash] options - Symbol-keyed hash
    # @option options [Integer,false,nil] :threshold (0)
    #                           the number of remaining nodes allowed when
    #                           determining whether or not to continue blocking.
    #                           If `false` or `nil` are provided, the default
    #                           will be substituted.
    #
    def initialize( zk, paths, options={} )
      paths = [paths] if paths.kind_of? String # old style single-node support

      @zk         = zk
      @paths      = paths.dup
      @options    = options.dup
      @threshold  = options[:threshold] || 0
      raise ZK::Exceptions::BadArguments, <<-EOBADARG unless @threshold.kind_of? Integer
        options[:threshold] must be an Integer. Got #{@threshold.inspect}."
      EOBADARG

      @watched_paths = []
      @remaining_paths = paths.dup

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
    #   seconds after which, if the threshold has not been met, a LockWaitTimeoutError will
    #   be raised in all waiting threads.
    #
    def block_until_deleted(opts={})
      timeout = opts[:timeout]

      @mutex.synchronize do
        raise InvalidStateError, "Already fired for #{status_string}" if @result
        register_callbacks

        watch_appropriate_nodes

        return finish_blocking if threshold_met?

        logger.debug { "ok, going to block: #{status_string}" }

        @blocked = BLOCKED
        @cond.broadcast                 # wake threads waiting for @blocked to change

        wait_for_result(timeout)

        @blocked = NOT_ANYMORE

        logger.debug { "got result: #{@result.inspect}. #{status_string}" }

        case @result
        when :deleted
          logger.debug { "enough paths were deleted. #{status_string}" }
          return true
        when TIMED_OUT
          raise ZK::Exceptions::LockWaitTimeoutError,
            "timed out waiting for #{timeout.inspect} seconds for deletion of paths. #{status_string}"
        when INTERRUPTED
          raise ZK::Exceptions::WakeUpException
        when ZOO_EXPIRED_SESSION_STATE
          raise Zookeeper::Exceptions::SessionExpired
        when ZOO_CONNECTING_STATE
          raise Zookeeper::Exceptions::NotConnected
        when ZOO_CLOSED_STATE
          raise Zookeeper::Exceptions::ConnectionClosed
        else
          raise "Hit unexpected case in block_until_node_deleted, result was: #{@result.inspect}. #{status_string}"
        end
      end
    ensure
      unregister_callbacks
    end

    private
      def status_string
        "paths: #{paths.inspect}, remaining: #{remaining_paths.inspect}, options: #{options.inspect}"
      end

      # this method must be synchronized on @mutex, obviously
      def wait_for_result(timeout)
        # do the deadline maths
        time_to_stop = timeout ? (Time.now + timeout) : nil # slight time slippage between here
                                                            #
        until @result                                       #
          if timeout                                        # and here
            now = Time.now

            if @result
              return
            elsif (now >= time_to_stop)
              @result = TIMED_OUT
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
        paths.each do |path|
          @subs << zk.register(path, &method(:node_deletion_cb))
        end

        [:expired_session, :connecting, :closed].each do |sym|
          @subs << zk.event_handler.register_state_handler(sym, &method(:session_cb))
        end
      end

      def node_deletion_cb(event)
        @mutex.synchronize do
          return if @result

          if event.node_deleted? or not zk.exists?(event.path, :watch => true)
            finish_node(event.path)
          end
        end
      end

      def session_cb(event)
        @mutex.synchronize do
          return if @result
          @result = event.state
          @cond.broadcast
        end
      end

      # must be synchronized on @mutex
      def threshold_met?
        return true if remaining_paths.size <= threshold
      end

      # ensures that threshold + 1 nodes are being watched
      def watch_appropriate_nodes
        remaining_paths.last( threshold + 1 ).reverse_each do |path|
          next if watched_paths.include? path
          watched_paths << path
          finish_node(path) unless zk.exists?(path, :watch => true)
        end
      end

      # must be synchronized on @mutex
      def finish_blocking
        @result = :deleted
        @blocked = NOT_ANYMORE
        @cond.broadcast # wake any waiting threads
        true
      end

      def finish_node(path)
        remaining_paths.delete path
        watched_paths.delete   path

        watch_appropriate_nodes

        finish_blocking if threshold_met?
      end
  end # MultiNodeDeletionWatcher
end # ZK
