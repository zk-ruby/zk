require File.join(File.dirname(__FILE__), %w[spec_helper])

describe ZK::ClientPool do

  before(:each) do
    @pool_size = 2
    @connection_pool = ZK::ClientPool.new("localhost:#{ZK_TEST_PORT}", @pool_size, :watcher => :default)
#     unless defined?(::JRUBY_VERSION)
#       @connection_pool.connections.each { |cp| cp.set_debug_level(Zookeeper::ZOO_LOG_LEVEL_DEBUG) }
#     end
  end

  after(:each) do
    @connection_pool.close_all! unless @connection_pool.closed?

    zk = ZK.new("localhost:#{ZK_TEST_PORT}")
    zk.delete('/test_pool') rescue ZK::Exceptions::NoNode
    zk.close!
  end

  it "should allow you to execute commands on a connection" do
    @connection_pool.with_connection do |zk|
      zk.create("/test_pool", "", :mode => :ephemeral)
      zk.exists?("/test_pool").should be_true
    end
  end

  describe :method_missing do
    it %[should allow you to execute commands on the connection pool itself] do
      @connection_pool.create('/test_pool', '', :mode => :persistent)
      wait_until(2) { @connection_pool.exists?('/test_pool') }
      @connection_pool.exists?('/test_pool').should be_true
    end
  end


  describe :close_all! do
    it %[should shutdown gracefully] do
      release_q  = Queue.new

      @about_to_block = false

      open_th = Thread.new do
        @connection_pool.with_connection do |cnx|
          @about_to_block = true
          # wait for signal to release our connection
          release_q.pop
        end
      end

      wait_until(2) { @about_to_block }
      @about_to_block.should be_true

      release_q.num_waiting.should == 1

      closing_th = Thread.new do
        @connection_pool.close_all!
      end

      wait_until(2) { @connection_pool.closing? }
      @connection_pool.should be_closing

      lambda { @connection_pool.with_connection { |c| } }.should raise_error(ZK::Exceptions::PoolIsShuttingDownException)

      release_q << :ok_let_go

      wait_until(2) { @connection_pool.closed? }
      @connection_pool.should be_closed

      lambda do
        closing_th.join(1).should == closing_th
        open_th.join(1).should == open_th
      end.should_not raise_error
    end
  end

#   it "using non-blocking it should only let you checkout the pool size" do
#     @connection_pool.size.should == 2

#     ary = []

#     wait_until(2) { ary << @connection_pool.checkout(false) }
#     ary.length.should == 1

#     @connection_pool.size.should == 1

#     (@pool_size - 1).times do
#       ary << @connection_pool.checkout(false)
#     end

#     @connection_pool.checkout(false).should be_false


#   end

  it "should allow watchers still" do
    pending "No idea why this is busted"

    @callback_called = false

    @path = '/_testWatch'

    @connection_pool.checkout do |zk|
      zk.delete(@path) rescue ZK::Exceptions::NoNode
    end

    @connection_pool.checkout do |zk|
      $stderr.puts "registering callback"
      zk.watcher.register(@path) do |event|
        $stderr.puts "callback fired! event: #{event.inspect}"

        @callback_called = true
        event.path.should == @path
        $stderr.puts "signaling other waiters"
      end

      $stderr.puts "setting up watcher"
      zk.exists?(@path, :watch => true).should be_false
    end

    @connection_pool.checkout do |zk|
      $stderr.puts "creating path"
      zk.create(@path, "", :mode => :ephemeral).should == @path
    end

    wait_until(1) { @callback_called }

    @callback_called.should be_true
  end
end
