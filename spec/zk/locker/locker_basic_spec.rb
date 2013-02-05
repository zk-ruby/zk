require 'spec_helper'

# this is a remnant of the old Locker class, but a good test of what's expected
# from ZK::Client#locker
#
describe 'ZK::Client#locker' do
  include_context 'connection opts'

  before(:each) do
    @zk = ZK.new(*connection_args)
    @zk2 = ZK.new(*connection_args)
    @zk3 = ZK.new(*connection_args)
    @connections = [@zk, @zk2, @zk3]
    wait_until { @connections.all? { |c| c.connected? } }
    logger.debug { "all connections connected" }
    @path_to_lock = "/lock_tester"
  end

  after(:each) do
    @zk.close!
    @zk2.close!
    @zk3.close!
    wait_until { @connections.all? { |c| c.closed? } } 
  end

  it "should be able to acquire the lock if no one else is locking it" do
    @zk.locker(@path_to_lock).lock.should be_true
  end

  it "should not be able to acquire the lock if someone else is locking it" do
    @zk.locker(@path_to_lock).lock.should be_true
    @zk2.locker(@path_to_lock).lock.should be_false
  end

  it "should assert properly if lock is acquired" do
    @zk.locker(@path_to_lock).assert.should be_false
    l = @zk2.locker(@path_to_lock)
    l.lock.should be_true
    l.assert.should be_true
  end

  it "should be able to acquire the lock after the first one releases it" do
    lock1 = @zk.locker(@path_to_lock)
    lock2 = @zk2.locker(@path_to_lock)
    
    lock1.lock.should be_true
    lock2.lock.should be_false
    lock1.unlock
    lock2.lock.should be_true
  end

  it "should be able to acquire the lock if the first locker goes away" do
    lock1 = @zk.locker(@path_to_lock)
    lock2 = @zk2.locker(@path_to_lock)

    lock1.lock.should be_true
    lock2.lock.should be_false
    @zk.close!
    lock2.lock.should be_true
  end

  it "should be able to handle multi part path locks" do
    @zk.locker("my/multi/part/path").lock.should be_true
  end

  describe :with_lock do
    # TODO: reorganize these tests so Convenience testing is done somewhere saner
    #
    # this tests ZK::Client::Conveniences, maybe shouldn't be *here*
    describe 'Client::Conveniences' do
      it %[should yield the lock instance to the block] do
        @zk.with_lock(@path_to_lock) do |lock|
          lock.should_not be_nil
          lock.should be_kind_of(ZK::Locker::LockerBase)
          lambda { lock.assert! }.should_not raise_error
        end
      end

      it %[should yield a shared lock when :mode => shared given] do
        @zk.with_lock(@path_to_lock, :mode => :shared) do |lock|
          lock.should_not be_nil
          lock.should be_kind_of(ZK::Locker::SharedLocker)
          lambda { lock.assert! }.should_not raise_error
        end
      end

      it %[should take a timeout] do
        first_lock = @zk.locker(@path_to_lock)
        first_lock.lock.should be_true

        thread = Thread.new do
          begin
            @zk.with_lock(@path_to_lock, :wait => 0.01) do |lock|
              raise "NO NO NO!! should not have called the block!!"
            end
          rescue Exception => e
            @exc = e
          end
        end

        thread.join(2).should == thread
        @exc.should be_kind_of(ZK::Exceptions::LockWaitTimeoutError)
      end
    end

    describe 'LockerBase' do
      it "should blocking lock" do
        array = []
        first_lock = @zk.locker("mylock")
        first_lock.lock.should be_true
        array << :first_lock

        thread = Thread.new do
          @zk.locker("mylock").with_lock do
            array << :second_lock
          end
          array.length.should == 2
        end

        array.length.should == 1
        first_lock.unlock
        thread.join(10)
        array.length.should == 2
      end

      it %[should accept a :wait option] do
        array = []
        first_lock = @zk.locker("mylock")
        first_lock.lock.should be_true

        second_lock = @zk.locker("mylock")

        thread = Thread.new do
          begin
            second_lock.with_lock(:wait => 0.01) do
              array << :second_lock
            end
          rescue Exception => e
            @exc = e
          end
        end

        array.should be_empty
        thread.join(2).should == thread
        @exc.should_not be_nil
        @exc.should be_kind_of(ZK::Exceptions::LockWaitTimeoutError)
      end
    end
  end # with_lock
end


