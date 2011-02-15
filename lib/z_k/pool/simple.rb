module ZK
  module Pool
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
  end   # Pool
end     # ZK
