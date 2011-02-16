module ZK
  module Pool
    class Base
      def initialize
        @state = :init

        @connections = []
        @connections.extend(MonitorMixin)
        @checkin_cond = @connections.new_cond
      end

      # has close_all! been called on this ConnectionPool ?
      def closed?
        @connections.synchronize { @state == :closed }
      end

      def closing?
        @connections.synchronize { @state == :closing }
      end

      def open?
        @connections.synchronize { @state == :open }
      end

      # close all the connections on the pool
      # @param optional Boolean graceful allow the checked out connections to come back first?
      def close_all!(graceful=false)
        @connections.synchronize do 
          return unless open?
          @state = :closing

          @checkin_cond.wait_until { @pool.size == @connections.length }

          @pool.clear

          while cnx = @connections.shift
            cnx.close!
          end

          @state = :closed
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

      def checkout(blocking=true) #:nodoc:
        assert_open!
        debugger

        @pool.pop(!blocking)
      rescue ThreadError
        false
      end

      def checkin(connection) #:nodoc:
        @connections.synchronize do
          @pool.push(connection)
          @checkin_cond.signal
        end
      end

      #lock lives on past the connection checkout
      def locker(path)
        with_connection do |connection|
          connection.locker(path)
        end
      end

      #prefer this method if you can (keeps connection checked out)
      def with_lock(path, &block)
        with_connection do |connection|
          connection.locker(path).with_lock(&block)
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

      # DANGER! test only, array of all connections
      def connections #:nodoc:
        @connections
      end

      protected
        def assert_open!
          raise Exceptions::PoolIsShuttingDownException unless open? 
        end

        def populate_pool!(num_cnx)
          @connections.synchronize do
            num_cnx.times do
              connection = ZK.new(@host, @connection_args)
              @connections << connection
              checkin(connection)
              @state = :open
            end
          end
        end

    end # Base

    # create a connection pool useful for multithreaded applications
    # @example
    #   pool = ZK::Pool::Simple.new("localhost:2181", 10)
    #   pool.checkout do |zk|
    #     zk.create("/mynew_path")
    class Simple < Base

      # initialize a connection pool using the same optons as ZK.new
      # @param String host the same arguments as ZK.new
      # @param Integer number_of_connections the number of connections to put in the pool
      # @param optional Hash opts Options to pass on to each connection
      # @return ZK::ClientPool
      def initialize(host, number_of_connections=10, opts = {})
        super()
        @connection_args = opts

        @number_of_connections = number_of_connections
        @host = host
        @pool = ::Queue.new

        populate_pool!(@number_of_connections)
      end
    end # Simple

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

        opts = opts.symbolize_keys.reverse_merge(DEFAULT_OPTIONS)

        @min_clients = Integer(opts[:min_clients])
        @max_clients = Integer(opts[:max_clients])
        @connection_timeout = opts[:timeout]

        # for compatibility w/ ClientPool we'll use @connections for synchronization
        @pool = []            # currently available connections


        populate_pool!(@min_clients)
      end

      def checkin(connection)
        @connections.synchronize do
          @pool.unshift(connection)
          @checkin_cond.signal
        end
      end

      def checkout(blocking=true) 
        @connections.synchronize do
          begin
            assert_open!

            if @pool.length > 0
              return @pool.shift
            elsif can_grow_pool?
              return create_connection.tap { |cnx| @connections << cnx }
            elsif blocking
              @checkin_cond.wait_while { @pool.empty? }
              retry
            else
              return false
            end
          end
        end
      end

      protected
        def can_grow_pool?
          @connections.synchronize { @connections.size < @max_clients }
        end

        def create_connection
          ZK.new(@host, @connection_timeout, @connection_args)
        end
    end # Bounded
  end   # Pool
end     # ZK

