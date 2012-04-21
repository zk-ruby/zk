shared_context 'threaded client connection' do
  before do
    @connection_string = "localhost:#{ZK_TEST_PORT}"
    @zk = ZK::Client::Threaded.new(@connection_string).tap { |z| wait_until { z.connected? } }
    @zk.rm_rf('/test')
  end

  after do
    @zk.rm_rf('/test')
    @zk.close!

    wait_until(2) { @zk.closed? }
  end
end

