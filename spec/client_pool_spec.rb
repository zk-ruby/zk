require File.join(File.dirname(__FILE__), %w[spec_helper])

describe ZK::ClientPool do

  before(:each) do
    @pool_size = 2
    @connection_pool = ZK::ClientPool.new("localhost:#{ZK_TEST_PORT}", @pool_size, :watcher => :default)
    unless defined?(::JRUBY_VERSION)
      @connection_pool.connections.each { |cp| cp.set_debug_level(Zookeeper::ZOO_LOG_LEVEL_DEBUG) }
    end
  end

  after(:each) do
    @connection_pool.close_all!
  end

  it "should allow you to execute commands on a connection" do
    @connection_pool.checkout do |zk|
      zk.create("/test_pool", "", :mode => :ephemeral)
      zk.exists?("/test_pool").should be_true
    end
  end

  it "using non-blocking it should only let you checkout the pool size" do
    @connection_pool.size.should == 2

    ary = []

    wait_until(2) { ary << @connection_pool.checkout(false) }
    ary.length.should == 1

    @connection_pool.size.should == 1

    (@pool_size - 1).times do
      ary << @connection_pool.checkout(false)
    end

    @connection_pool.checkout(false).should be_false
  end
  
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
