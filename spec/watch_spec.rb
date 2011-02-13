require File.join(File.dirname(__FILE__), %w[spec_helper])

describe ZK do

  before(:each) do
    @zk = ZK.new("localhost:#{ZK_TEST_PORT}", :watcher => :default)
    @path = "/_testWatch"
    wait_until { @zk.connected? }
  end

  after(:each) do
    @zk.delete(@path) rescue ZK::Exceptions::NoNode
    @zk.close!
    wait_until { !@zk.connected? }
  end

  it "should call back to path registers" do
    locker = Mutex.new
    callback_called = false

    @zk.watcher.register(@path) do |event|
      locker.synchronize do
        callback_called = true
      end
      event.path.should == @path
    end

    @zk.exists?(@path, :watch => true)
    @zk.create(@path, "", :mode => :ephemeral)

    wait_until(5) { locker.synchronize { callback_called } }
    callback_called.should be_true
  end

  it %[should allow the block to renew the watch] do
    @count = 0

    @zk.watcher.register(@path) do |event|
      @count += 1
      event.renew_watch!
    end

    @zk.exists?(@path, :watch => true).should be_false
    @zk.create(@path, "", :mode => :ephemeral)

    wait_until(2) { @count > 0 }
    @count.should == 1

    @zk.delete(@path)
    wait_until(2) { @count > 1 }

    @count.should == 2
  end
end
