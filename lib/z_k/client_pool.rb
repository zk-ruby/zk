module ZK
  # create a connection pool useful for multithreaded applications
  # @example
  #   pool = ZK::ClientPool.new("localhost:2181", 10)
  #   pool.checkout do |zk|
  #     zk.create("/mynew_path")
  class ClientPool

    # initialize a connection pool using the same optons as ZK.new
    # @param String host the same arguments as ZK.new
    # @param Integer number_of_connections the number of connections to put in the pool
    # @param optional Hash opts Options to pass on to each connection
    # @return ZK::ClientPool
    def initialize(host, number_of_connections=10, opts = {})
      @connection_args = opts

      @status = :init
      
      @number_of_connections = number_of_connections
      @host = host
      @pool = ::Queue.new

      @connections = []
      @connections.extend(MonitorMixin)
      @checkin_cond = @connections.new_cond

      populate_pool!
    end

    # has close_all! been called on this ConnectionPool ?
    def closed?
      @connections.synchronize { @status == :closed }
    end

    def closing?
      @connections.synchronize { @status == :closing }
    end

    def open?
      @connections.synchronize { @status == :open }
    end

    # close all the connections on the pool
    # @param optional Boolean graceful allow the checked out connections to come back first?
    def close_all!(graceful=false)
      @connections.synchronize do 
        return unless open?
        @status = :closing

        @checkin_cond.wait_until { @pool.size == @connections.length }

        @pool.clear

        while cnx = @connections.shift
          cnx.close!
        end

        @status = :closed
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

    def checkout(blocking = true, &block) #:nodoc:
      assert_open!

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

  private
    def assert_open!
      raise Exceptions::PoolIsShuttingDownException unless open? 
    end

    def populate_pool!
      @connections.synchronize do
        @number_of_connections.times do
          connection = ZK.new(@host, @connection_args)
          @connections << connection
          checkin(connection)
          @status = :open
        end
      end
    end
  end
end
