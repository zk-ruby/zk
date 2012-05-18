module ZK
  class NodeDeletionWatcher
    include Zookeeper::Constants
    include Exceptions
    include Logging

    attr_reader :zk, :path

    def initialize(zk, path)
      @zk     = zk
      @path   = path.dup

      @subs   = []

      @mutex  = Monitor.new # ffs, 1.8.7 compatibility w/ timeouts
      @cond   = @mutex.new_cond

      @blocked  = :not_yet
      @result   = nil
    end

    def done?
      @mutex.synchronize { !!@result }
    end

    def blocked?
      @mutex.synchronize { @blocked == :yes }
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
        return true unless @blocked == :not_yet

        start = Time.now
        time_to_stop = timeout ? (start + timeout) : nil

        @cond.wait(timeout)

        if (time_to_stop and (Time.now > time_to_stop)) and (@blocked == :not_yet)
          return nil
        end

        (@blocked == :not_yet) ? nil : true
      end
    end

    # cause a thread blocked us to be awakened and have a WakeUpException
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
        when :not_yet, :yes
          @result = :interrupted
          @cond.broadcast
        else
          return
        end
      end
    end

    def block_until_deleted
      @mutex.synchronize do
        raise InvalidStateError, "Already fired for #{path}" if @result
        register_callbacks

        return true unless zk.exists?(path, :watch => true)

        logger.debug { "ok, going to block: #{path}" }

        while true
          @blocked = :yes
          @cond.broadcast                 # wake threads waiting for @blocked to change
          @cond.wait_until { @result }    # wait until we get a result
          @blocked = :not_anymore

          case @result
          when :deleted
            logger.debug { "path #{path} was deleted" }
            return true
          when :interrupted
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
      end
    ensure
      unregister_callbacks
    end

    private
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
            @result = :deleted
            @cond.broadcast
          else
            unless zk.exists?(path, :watch => true)
              @result = :deleted
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

