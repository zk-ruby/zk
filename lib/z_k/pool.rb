module ZK
  module Pool
    class Base
      attr_reader :connections #:nodoc:

      def initialize
        @state = :init

        @mutex  = Monitor.new
        @checkin_cond = @mutex.new_cond
        
        @connections = []     # all connections we control
        @pool = []            # currently available connections

        # this is required for 1.8.7 compatibility
        @on_connection_subs = {}
        @on_connection_subs.extend(MonitorMixin)
      end

      # has close_all! been called on this ConnectionPool ?
      def closed?
        @state == :closed
      end

      # is the pool shutting down?
      def closing?
        @state == :closing
      end

      # is the pool initialized and in normal operation?
      def open?
        @state == :open
      end

      # has the pool entered the take-no-prisoners connection closing part of shutdown?
      def forced?
        @state == :forced
      end

      # close all the connections on the pool
      # @param optional Boolean graceful allow the checked out connections to come back first?
      def close_all!
        @mutex.synchronize do 
          return unless open?
          @state = :closing

          @checkin_cond.wait_until { (@pool.size == @connections.length) or closed? }

          force_close!
        end
      end

      # calls close! on all connection objects, whether or not they're back in the pool
      # this is DANGEROUS!
      def force_close! #:nodoc:
        @mutex.synchronize do
          return if (closed? or forced?)
          @state = :forced

          @pool.clear

          while cnx = @connections.shift
            cnx.close!
          end

          @state = :closed

          # free any waiting 
          @checkin_cond.broadcast
        end
      end

      # yields next available connection to the block
      #
      # raises PoolIsShuttingDownException immediately if close_all! has been
      # called on this pool
      def with_connection
        assert_open!

        cnx = checkout(true)
        yield cnx
      ensure
        checkin(cnx)
      end

      #lock lives on past the connection checkout
      def locker(path)
        with_connection do |connection|
          connection.locker(path)
        end
      end

      #prefer this method if you can (keeps connection checked out)
      def with_lock(name, opts={}, &block)
        with_connection do |connection|
          connection.with_lock(name, opts, &block)
        end
      end

      # handle all
      def method_missing(meth, *args, &block)
        with_connection do |connection|
          connection.__send__(meth, *args, &block)
        end
      end

      def size #:nodoc:
        @connection.synchronize { @pool.size }
      end

      def pool_state #:nodoc:
        @state
      end

      protected
        def synchronize
          @mutex.synchronize { yield }
        end

        def assert_open!
          raise Exceptions::PoolIsShuttingDownException unless open? 
        end

    end # Base

    # like a Simple pool but has high/low watermarks, and can grow dynamically as needed
    class Bounded < Base
      DEFAULT_OPTIONS = {
        :timeout      => 10,
        :min_clients  => 1,
        :max_clients  => 10,
      }.freeze

      # opts:
      # * <tt>:timeout</tt>: connection establishement timeout
      # * <tt>:min_clients</tt>: how many clients should be start out with
      # * <tt>:max_clients</tt>: the maximum number of clients we will create in response to demand
      def initialize(host, opts={})
        super()
        @host = host
        @connection_args = opts

        opts = DEFAULT_OPTIONS.merge(opts)

        @min_clients = Integer(opts.delete(:min_clients))
        @max_clients = Integer(opts.delete(:max_clients))
        @connection_timeout = opts.delete(:timeout)

        @count_waiters = 0

        @mutex.synchronize do
          populate_pool!(@min_clients)
          @state = :open
        end
      end

      # returns the current number of allocated clients in the pool (not
      # available clients)
      def size
        @mutex.synchronize { @connections.length }
      end

      # clients available for checkout (at time of call)
      def available_size
        @mutex.synchronize { @pool.length }
      end

      def checkin(connection)
        @mutex.synchronize do
          if @pool.include?(connection)
            logger.debug { "Pool already contains connection: #{connection.object_id}, @connections.include? #{@connections.include?(connection).inspect}" }
            return
          end

          @pool << connection

          @checkin_cond.signal
        end
      end

      # number of threads waiting for connections
      def count_waiters #:nodoc:
        @mutex.synchronize { @count_waiters }
      end

      def checkout(blocking=true) 
        raise ArgumentError, "checkout does not take a block, use .with_connection" if block_given?
        @mutex.synchronize do
          logger.debug { "Thread: #{Thread.current.object_id} entered checkout" }
          begin
            while true
              assert_open!

              if @pool.length > 0
                logger.debug { "@pool.size: #{@pool.size}" }
                cnx = @pool.shift
                logger.debug { "@pool.size: #{@pool.size}" }
                
                # If the cnx isn't connected? then remove it from the pool and dispose of it.
                # Create a new connection and then iterate again. Given the
                # asynchronous nature that connections are added to the pool,
                # this is the only sane/safe way to do this
                #
                unless cnx.connected?
                  logger.debug { "cnx: #{cnx.object_id} is not connected, disposing and adding new connection" }
                  @connections.delete(cnx)
                  cnx.close!
                  next
                end

                logger.debug { "returning connection: #{cnx.object_id}" }
                # otherwise we return the cnx
                return cnx
              elsif can_grow_pool?
                add_connection!
                next
              elsif blocking
                @checkin_cond.wait_while { @pool.empty? and open? }
                next
              else
                return false
              end
            end # while 
          ensure
            logger.debug { "Thread: #{Thread.current.object_id} exitng checkout" }
          end
        end
      end

      # @private
      def can_grow_pool?
        @mutex.synchronize { @connections.size < @max_clients }
      end

      protected
        def synchronize_with_waiter_count
          @mutex.synchronize do
            begin
              @count_waiters += 1 
              yield
            ensure
              @count_waiters -= 1
            end
          end
        end

        def populate_pool!(num_cnx)
          num_cnx.times { add_connection! }
        end

        def add_connection!
          @mutex.synchronize do
            cnx = create_connection
            @connections << cnx 
            logger.debug { "added connection #{cnx.object_id}  to @connections" }

            do_checkin = lambda do
              logger.debug { "on_connected called for cnx #{cnx.object_id}" }
              checkin(cnx)
            end

            if cnx.connected?
              do_checkin.call
              return
            else
              @on_connection_subs.synchronize do

                sub = cnx.on_connected do 
                  @on_connection_subs.synchronize do
                    if sub = @on_connection_subs.delete(cnx)
                      sub.unsubscribe
                      do_checkin.call
                    end
                  end
                end

                @on_connection_subs[cnx] = sub
              end
            end

          end # synchronize
        end

        def create_connection
          ZK.new(@host, @connection_timeout, @connection_args)
        end
    end # Bounded

    # create a connection pool useful for multithreaded applications
    #
    # Will spin up +number_of_connections+ at creation time and remain fixed at
    # that number for the life of the pool.
    #
    # ==== Example
    #   pool = ZK::Pool::Simple.new("localhost:2181", 10)
    #   pool.checkout do |zk|
    #     zk.create("/mynew_path")
    #   end
    class Simple < Bounded
      # initialize a connection pool using the same optons as ZK.new
      # @param String host the same arguments as ZK.new
      # @param Integer number_of_connections the number of connections to put in the pool
      # @param optional Hash opts Options to pass on to each connection
      # @return ZK::ClientPool
      def initialize(host, number_of_connections=10, opts = {})
        opts = opts.dup
        opts[:max_clients] = opts[:min_clients] = number_of_connections.to_i

        super(host, opts)
      end
    end # Simple
  end   # Pool
end     # ZK

