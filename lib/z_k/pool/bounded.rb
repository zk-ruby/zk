module ZK
  module Pool
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
    end # BoundedClient
  end   # Pool
end     # ZK

