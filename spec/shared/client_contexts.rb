shared_context 'connection opts' do
  let(:connection_opts) { { :thread => :per_callback, :timeout => 5 } }
  let(:connection_host) { "#{ZK.default_host}:#{ZK.test_port}" }
  let(:connection_args) { [connection_host, connection_opts] }
end

shared_context 'threaded client connection' do
  include_context 'connection opts'

  before do
    logger.debug { "threaded client connection - begin before hook" }

    @connection_string = "localhost:#{ZK.test_port}"
    @base_path = '/zktests'
    @zk = ZK::Client::Threaded.new(*connection_args).tap { |z| wait_until { z.connected? } }
    @threadpool_exception = nil
    @zk.on_exception { |e| @threadpool_exception = e }
    @zk.rm_rf(@base_path)

    logger.debug { "threaded client connection - end before hook" }
  end

  after do
#     raise @threadpool_exception if @threadpool_exception
    logger.debug { "threaded client connection - after hook" }

    if @zk.closed?
      logger.debug { "zk was closed, calling reopen" }
      @zk.reopen 
    end

    wait_until(5) { @zk.connected? }
    
    @zk.rm_rf(@base_path)
    @zk.close!
    wait_until(5) { @zk.closed? }

    logger.debug { "threaded client connection - end after hook" }
  end
end


