require File.join(File.dirname(__FILE__), %w[spec_helper])

describe ZK::Locker do

  before(:each) do
    @zk = ZK.new("localhost:#{ZK_TEST_PORT}")
    @zk2 = ZK.new("localhost:#{ZK_TEST_PORT}")
    wait_until{ @zk.connected? && @zk2.connected? }
    @path_to_lock = "/lock_tester"
  end

  after(:each) do
    @zk.close!
    @zk2.close!
    wait_until{ !@zk.connected? && !@zk2.connected? }
  end

  it "should be able to acquire the lock if no one else is locking it" do
    @zk.locker(@path_to_lock).lock!.should be_true
  end

  it "should not be able to acquire the lock if someone else is locking it" do
    @zk.locker(@path_to_lock).lock!.should be_true
    @zk2.locker(@path_to_lock).lock!.should be_false
  end

  it "should be able to acquire the lock after the first one releases it" do
    lock1 = @zk.locker(@path_to_lock)
    lock2 = @zk2.locker(@path_to_lock)
    
    lock1.lock!.should be_true
    lock2.lock!.should be_false
    lock1.unlock!
    lock2.lock!.should be_true
  end

  it "should be able to acquire the lock if the first locker goes away" do
    lock1 = @zk.locker(@path_to_lock)
    lock2 = @zk2.locker(@path_to_lock)

    lock1.lock!.should be_true
    lock2.lock!.should be_false
    @zk.close!
    lock2.lock!.should be_true
  end

  it "should be able to handle multi part path locks" do
    @zk.locker("my/multi/part/path").lock!.should be_true
  end

  it "should blocking lock" do
    array = []
    first_lock = @zk.locker("mylock")
    first_lock.lock!.should be_true
    array << :first_lock

    thread = Thread.new do
      @zk.locker("mylock").with_lock do
        array << :second_lock
      end
      array.length.should == 2
    end

    array.length.should == 1
    first_lock.unlock!
    thread.join(10)
    array.length.should == 2
  end
end
