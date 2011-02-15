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
  end   # Pool
end     # ZK

