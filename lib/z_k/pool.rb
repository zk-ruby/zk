module ZK
  module Pool
    class Base
      attr_reader :connections #:nodoc:

      def initialize
        @state = :init

        @connections = []
        @connections.extend(MonitorMixin)
        @checkin_cond = @connections.new_cond
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
        synchronize do 
          return unless open?
          @state = :closing

          @checkin_cond.wait_until { (@pool.size == @connections.length) or closed? }

          force_close!
        end
      end

      # calls close! on all connection objects, whether or not they're back in the pool
      # this is DANGEROUS!
      def force_close! #:nodoc:
        synchronize do
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
        @pool.size
      end

      def pool_state #:nodoc:
        @state
      end

      protected
        def synchronize
          @connections.synchronize { yield }
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

        # for compatibility w/ ClientPool we'll use @connections for synchronization
        @pool = []            # currently available connections

        synchronize do
          populate_pool!(@min_clients)
          @state = :open
        end
      end

      # returns the current number of allocated clients in the pool (not
      # available clients)
      def size
        @connections.length
      end

      # clients available for checkout (at time of call)
      def available_size
        @pool.length
      end

      def checkin(connection)
        synchronize do
          return if @pool.include?(connection)

          @pool.unshift(connection)
          @checkin_cond.signal
        end
      end

      # number of threads waiting for connections
      def count_waiters #:nodoc:
        @count_waiters
      end

      def checkout(blocking=true) 
        raise ArgumentError, "checkout does not take a block, use .with_connection" if block_given?
        synchronize_with_waiter_count do
          while true
            assert_open!

            if @pool.length > 0
              cnx = @pool.shift
              
              # if the cnx isn't connected? then remove it from the pool and go
              # through the loop again. when the cnx's on_connected event fires, it
              # will add the connection back into the pool
              next unless cnx.connected?

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
          end
        end
      end

      protected
        def synchronize_with_waiter_count
          synchronize do
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
          synchronize do
            cnx = create_connection
            @connections << cnx 

            cnx.on_connected { checkin(cnx) }
          end
        end

        def can_grow_pool?
          synchronize { @connections.size < @max_clients }
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

