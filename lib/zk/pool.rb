module ZK
  module Pool
    # Base class for a ZK connection pool. There are some applications that may
    # require high synchronous throughput, which would be a suitable use for a
    # connection pool. The ZK::Client::Threaded class is threadsafe, so it's
    # not a problem accessing it from multiple threads, but it is limited to
    # one outgoing synchronous request at a time, which could cause throughput
    # issues for apps that are making very heavy use of zookeeper.
    #
    # The problem with using a connection pool is the added complexity when you
    # try to use watchers. It may be possible to register a watch with one
    # connection, and then call `:watch => true` on a different connection if
    # you're not careful. Events delivered as part of an event handler have a
    # `zk` attribute which can be used to access the connection that the
    # callback is registered with.
    #
    # Unless you're sure you *need* a connection pool, then avoid the added
    # complexity.
    #
    class Base
      include Logger

      attr_reader :connections #:nodoc:

      def initialize
        @state = :init

        @mutex  = Monitor.new
        @checkin_cond = @mutex.new_cond

        @connections = []     # all connections we control
        @pool = []            # currently available connections

        # this is required for 1.8.7 compatibility
        @on_connected_subs = {}
        @on_connected_subs.extend(MonitorMixin)
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
      # @private
      def force_close!
        @mutex.synchronize do
          return if (closed? or forced?)
          @state = :forced

          @pool.clear

          until @connections.empty?
            if cnx = @connections.shift
              cnx.close!
            end
          end

          @state = :closed

          # free any waiting
          @checkin_cond.broadcast
        end
      end

      # @private
      def wait_until_closed
        @mutex.synchronize do
          @checkin_cond.wait_until { @state == :closed }
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
        @mutex.synchronize { @pool.size }
      end

      def pool_state #:nodoc:
        @state
      end

      private
        def synchronize
          @mutex.synchronize { yield }
        end

        def assert_open!
          raise Exceptions::PoolIsShuttingDownException, "pool is shutting down" unless open?
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

          @checkin_cond.broadcast
        end
      end

      # number of threads waiting for connections
      def count_waiters #:nodoc:
        @mutex.synchronize { @count_waiters }
      end

      def checkout(blocking=true)
        raise ArgumentError, "checkout does not take a block, use .with_connection" if block_given?
        @mutex.lock
        begin
          while true
            assert_open!

            if @pool.length > 0
              cnx = @pool.shift

              # XXX(slyphon): not really sure how this case happens, but protect against it as we're
              # seeing an issue in production
              next if cnx.nil?

              # if the connection isn't connected, then set up an on_connection
              # handler and try the next one in the pool
              unless cnx.connected?
                logger.debug { "connection #{cnx.object_id} is not connected" }
                handle_checkin_on_connection(cnx)
                next
              end

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
          @mutex.unlock rescue nil
        end
      end

      # @private
      def can_grow_pool?
        @mutex.synchronize { @connections.size < @max_clients }
      end

      private
        def populate_pool!(num_cnx)
          num_cnx.times { add_connection! }
        end

        def add_connection!
          @mutex.synchronize do
            cnx = create_connection
            @connections << cnx

            handle_checkin_on_connection(cnx)
          end # synchronize
        end

        def handle_checkin_on_connection(cnx)
          @mutex.synchronize do
            do_checkin = lambda do
              checkin(cnx)
            end

            if cnx.connected?
              do_checkin.call
              return
            else
              @on_connected_subs.synchronize do

                sub = cnx.on_connected do
                  # this synchronization is to prevent a race between setting up the subscription
                  # and assigning it to the @on_connected_subs hash. It's possible that the callback
                  # would fire before we had a chance to add the sub to the hash.
                  @on_connected_subs.synchronize do
                    if sub = @on_connected_subs.delete(cnx)
                      sub.unsubscribe
                      do_checkin.call
                    end
                  end
                end

                @on_connected_subs[cnx] = sub
              end
            end
          end
        end

        def create_connection
          ZK.new(@host, @connection_args.merge(:timeout => @connection_timeout))
        end
    end # Bounded

    # create a connection pool useful for multithreaded applications
    #
    # Will spin up `number_of_connections` at creation time and remain fixed at
    # that number for the life of the pool.
    #
    # @example
    #
    #   pool = ZK::Pool::Simple.new("localhost:2181", :timeout => 10)
    #   pool.checkout do |zk|
    #     zk.create("/mynew_path")
    #   end
    #
    class Simple < Bounded
      # initialize a connection pool using the same optons as ZK.new
      # @param [String] host the same arguments as ZK.new
      # @param [Integer] number_of_connections the number of connections to put in the pool
      # @param [Hash] opts Options to pass on to each connection
      # @return [ZK::ClientPool]
      def initialize(host, number_of_connections=10, opts = {})
        opts = opts.dup
        opts[:max_clients] = opts[:min_clients] = number_of_connections.to_i

        super(host, opts)
      end
    end # Simple
  end   # Pool
end     # ZK

