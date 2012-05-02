shared_context 'connection opts' do
  let(:connection_opts) { { :thread => :per_callback, :timeout => 5 } }
  let(:connection_host) { "localhost:#{ZK.test_port}" }
  let(:connection_args) { [connection_host, connection_opts] }
end

shared_context 'threaded client connection' do
  include_context 'connection opts'

  before do
    @connection_string = "localhost:#{ZK.test_port}"
    @base_path = '/zktests'
    @zk = ZK::Client::Threaded.new(*connection_args).tap { |z| wait_until { z.connected? } }
    @zk.on_exception { |e| raise e }
    @zk.rm_rf(@base_path)
  end

  after do
    @zk.reopen if @zk.closed?
    wait_until(2) { @zk.connected? }

#       zk = ZK.open(*connection_args) { |z| z.rm_rf(@base_path) }
    
    @zk.rm_rf(@base_path)
    @zk.close!
    wait_until(2) { @zk.closed? }
  end
end


