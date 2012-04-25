shared_context 'threaded client connection' do
  before do
    @connection_string = "localhost:#{ZK_TEST_PORT}"
    @base_path = '/zktests'
    @zk = ZK::Client::Threaded.new(@connection_string).tap { |z| wait_until { z.connected? } }
    @zk.on_exception { |e| raise e }
    @zk.rm_rf(@base_path)
  end

  after do
    @zk.rm_rf(@base_path)
    @zk.close!

    wait_until(2) { @zk.closed? }
  end
end

