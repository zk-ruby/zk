shared_context 'connection opts' do
  let(:connection_opts) { { :thread => :per_callback, :timeout => 5 } }
  let(:connection_host) { "#{ZK.default_host}:#{ZK.test_port}" }
  let(:connection_args) { [connection_host, connection_opts] }
end

shared_context 'threaded client connection' do
  include_context 'connection opts'

  before do
#     logger.debug { "threaded client connection - begin before hook" }
    @connection_string = connection_host
    @base_path = '/zktests'
    @zk = ZK::Client::Threaded.new(*connection_args).tap { |z| wait_until { z.connected? } }
    @threadpool_exception = nil
    @zk.on_exception { |e| @threadpool_exception = e }
    @zk.rm_rf(@base_path)

    @orig_default_root_lock_node = ZK::Locker.default_root_lock_node
    ZK::Locker.default_root_lock_node = "#{@base_path}/_zklocking"

#     logger.debug { "threaded client connection - end before hook" }
  end

  after do
#     raise @threadpool_exception if @threadpool_exception
#     logger.debug { "threaded client connection - after hook" }

    @zk.close! if @zk and not @zk.closed?

    ZK.open(*connection_args) do |z|
      z.rm_rf(@base_path)
    end

    ZK::Locker.default_root_lock_node = @orig_default_root_lock_node

#     logger.debug { "threaded client connection - end after hook" }
  end
end


