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
      if opts[:watcher] and opts[:watcher] != :default
        raise "You cannot specify a custom watcher on a connection pool. You will be given an event_handler on each connection"
      else
        @connection_args[:watcher] = :default
      end
      @number_of_connections = number_of_connections
      @host = host
      @pool = ::Queue.new

      populate_pool!
    end

    # close all the connections on the pool
    # @param optional Boolean graceful allow the checked out connections to come back first?
    def close_all!(graceful=false)
      if graceful
        until @pool.num_waiting == 0 do
          sleep 0.1
        end
      else
        raise "Clients are still waiting for this pool" if @pool.num_waiting > 0
      end

      until @pool.size == 0 do
        @pool.pop.close!
      end
    end

    # checkout a connection from the pool - takes a block which will check it
    # back in after the block is finished
    # @param optional [Boolean] blocking If blocking is set to false then false will be returned
    #   if no connection is available
    # @yield [connection] The checked out connection
    def checkout(blocking = true, &block)
      if block
        checkout_checkin_with_block(block)
      else
        return @pool.pop(!blocking)
      end
    rescue ThreadError
      return false
    end

    def checkin(connection)
      @pool.push(connection)
    end

    #lock lives on past the connection checkout
    def locker(path)
      checkout do |connection|
        connection.locker(path)
      end
    end

    #prefer this method if you can (keeps connection checked out)
    def with_lock(path, &block)
      checkout do |connection|
        connection.locker(path).with_lock(&block)
      end
    end

    # handle all
    def method_missing(meth, *args, &block)
      checkout do |connection|
        connection.send(meth, *args, &block)
      end
    end

private

    def populate_pool!
      @number_of_connections.times do
        mutex, did_checkin = Mutex.new, false

        connection = ZK.new(@host, @connection_args)
        subscription = connection.watcher.register_state_handler(:connected) do |event, zk|
          mutex.synchronize do
            unless did_checkin
              checkin(zk)
              did_checkin = true
            end
          end
          subscription.unsubscribe
        end

        mutex.synchronize do
          # incase we missed the watcher
          if connection.connected? and not did_checkin
            subscription.unsubscribe
            checkin(connection)
            did_checkin = true
          end
        end
      end
    end

    def checkout_checkin_with_block(block)
      connection = checkout
      block.call(connection)
    ensure
      checkin(connection)
    end

  end
end
