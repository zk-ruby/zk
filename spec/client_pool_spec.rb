require File.join(File.dirname(__FILE__), %w[spec_helper])

describe ZK::ClientPool do

  before(:each) do
    @pool_size = 2
    @connection_pool = ZK::ClientPool.new("localhost:#{ZK_TEST_PORT}", @pool_size, :watcher => :default)
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
    connections = []
    wait_until {
      @connection_pool.checkout(false)
    }
    (@pool_size - 1).times do
      connections << @connection_pool.checkout(false)
    end
    @connection_pool.checkout(false).should be_false
  end
  
  it "should allow watchers still" do
    locker = Mutex.new
    callback_called = false
    @connection_pool.checkout do |zk|
      zk.watcher.register("/_testWatch") do |event, zk|
        locker.synchronize { callback_called = true }
        event.path.should == "/_testWatch"
      end
      zk.exists?("/_testWatch", :watch => true)
    end
    @connection_pool.checkout {|zk| zk.create("/_testWatch", "", :mode => :ephemeral) }
    wait_until { locker.synchronize { callback_called } }
    callback_called.should be_true
  end

end
