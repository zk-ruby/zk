require File.join(File.dirname(__FILE__), %w[spec_helper])

# this is a remnant of the old Locker class, but a good test of what's expected
# from ZK::Client#locker
#
describe 'ZK::Client#locker' do

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

describe ZK::Locker do
  before do
    @zk = ZK.new("localhost:#{ZK_TEST_PORT}", :watcher => :default)
    @zk2 = ZK.new("localhost:#{ZK_TEST_PORT}", :watcher => :default)
    @connections = [@zk, @zk2]

    wait_until{ @connections.all? {|c| c.connected?} }

    @path = "shlock"
    @root_lock_path = "/_zklocking/#{@path}"
  end

  after do
    @connections.each { |c| c.close! }
    wait_until { @connections.all? { |c| !c.connected? } }
  end


  describe :ReadLocker do
    before do
      @shared_locker  = ZK::Locker.shared_locker(@zk, @path)
      @shared_locker2 = ZK::Locker.shared_locker(@zk2, @path)
    end

    describe :lock! do
      describe 'non-blocking success' do
        before do
          @rval   = @shared_locker.lock!
          @rval2  = @shared_locker2.lock!
        end

        it %[should acquire the first lock] do
          @rval.should be_true
          @shared_locker.should be_locked
        end

        it %[should acquire the second lock] do
          @rval2.should be_true
          @shared_locker2.should be_locked
        end
      end

      describe 'non-blocking failure' do
        before do
          @zk.mkdir_p(@root_lock_path)
          @write_lock_path = @zk.create('/_zklocking/shlock/write', '', :mode => :ephemeral_sequential)
          @rval = @shared_locker.lock!
        end

        after do
          @zk.rm_rf('/_zklocking')
        end

        it %[should return false] do
          @rval.should be_false
        end

        it %[should not be locked] do
          @shared_locker.should_not be_locked
        end
      end

      describe 'blocking success' do
        before do
          @zk.mkdir_p(@root_lock_path)
          @write_lock_path = @zk.create('/_zklocking/shlock/write', '', :mode => :ephemeral_sequential)
          $stderr.sync = true
        end

        it %[should acquire the lock after the write lock is released] do
          ary = []

          @shared_locker.lock!.should be_false

          th = Thread.new do
            @shared_locker.lock!(true)
            ary << :locked
          end

          ary.should be_empty
          @shared_locker.should_not be_locked

          @zk.delete(@write_lock_path)

          th.join(2)

          wait_until(2) { !ary.empty? }
          ary.length.should == 1

          @shared_locker.should be_locked
        end
      end
    end
  end   # ReadLocker

  describe :WriteLocker do
    before do
      @ex_locker = ZK::Locker.exclusive_locker(@zk, @path)
      @ex_locker2 = ZK::Locker.exclusive_locker(@zk2, @path)
    end

    describe :lock! do
      describe 'non-blocking' do
        before do
          @rval = @ex_locker.lock!
          @rval2 = @ex_locker2.lock!
        end

        it %[should acquire the first lock] do
          @rval.should be_true
        end

        it %[should not acquire the second lock] do
          @rval2.should be_false
        end

        it %[should acquire the second lock after the first lock is released] do
          @ex_locker.unlock!.should be_true
          @ex_locker2.lock!.should be_true
        end

        it %[should acquire the second lock even if a read lock is added after] do
          pending "need to mock this out, too difficult to do live"

#           @read_lock_path = @zk.create('/_zklocking/shlock/read', '', :mode => :ephemeral_sequential)
#           @ex_locker.unlock!.should be_true
#           @ex_locker2.lock!.should be_true
        end
      end

      describe 'blocking' do
        before do
          @zk.mkdir_p(@root_lock_path)
          @read_lock_path = @zk.create('/_zklocking/shlock/read', '', :mode => :ephemeral_sequential)
        end

        it %[should block waiting for the lock] do
          ary = []

          @ex_locker.lock!.should be_false

          th = Thread.new do
            @ex_locker.lock!(true)
            ary << :locked
          end

          th.run
        
          ary.should be_empty
          @ex_locker.should_not be_locked

          @zk.delete(@read_lock_path)

          th.join(2)

          ary.length.should == 1
          @ex_locker.should be_locked
        end
      end
    end
  end
end

