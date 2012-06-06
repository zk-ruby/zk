shared_context 'connection opts' do
  let(:connection_opts) { { :thread => :per_callback, :timeout => 5 } }
  let(:connection_host) { "#{ZK.default_host}:#{ZK.test_port}" }
  let(:connection_args) { [connection_host, connection_opts] }
end

shared_context 'threaded client connection' do
  include_context 'connection opts'

  before do
    logger.debug { "threaded client connection - begin before hook" }
    @connection_string = connection_host
    @base_path = '/zktests'
    @zk = ZK::Client::Threaded.new(*connection_args).tap { |z| z.wait_until_connected }
    @threadpool_exception = nil
    @zk.on_exception { |e| @threadpool_exception = e }
    @zk.rm_rf(@base_path)

    @orig_default_root_lock_node = ZK::Locker.default_root_lock_node
    ZK::Locker.default_root_lock_node = "#{@base_path}/_zk/locks"

    @orig_default_election_root = ZK::Election.default_root_election_node
    ZK::Election.default_root_election_node = "#{@base_path}/_zk/elections"

    @orig_default_queue_root = ZK::MessageQueue.default_root_queue_node
    ZK::MessageQueue.default_root_queue_node = "#{@base_path}/_zk/queues"
  end

  after do
    @zk.close! if @zk and not @zk.closed?

    ZK.open(*connection_args) do |z|
      z.rm_rf(@base_path)
    end

    ZK::Election.default_root_election_node   = @orig_default_election_root
    ZK::Locker.default_root_lock_node         = @orig_default_root_lock_node
    ZK::MessageQueue.default_root_queue_node  = @orig_default_queue_root
  end
end


