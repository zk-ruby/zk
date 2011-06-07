require 'spec_helper'

# this is a remnant of the old Locker class, but a good test of what's expected
# from ZK::Client#locker
#
describe 'ZK::Client#locker' do

  before(:each) do
    @zk = ZK.new("localhost:#{ZK_TEST_PORT}")
    @zk2 = ZK.new("localhost:#{ZK_TEST_PORT}")
    @zk3 = ZK.new("localhost:#{ZK_TEST_PORT}")
    @connections = [@zk, @zk2, @zk3]
    wait_until { @connections.all? { |c| c.connected? } }
    @path_to_lock = "/lock_tester"
  end

  after(:each) do
    @zk.close!
    @zk2.close!
    @zk3.close!
    wait_until{ @connections.all? { |c| !c.connected? } } 
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
    @zk3 = ZK.new("localhost:#{ZK_TEST_PORT}")
    @connections = [@zk, @zk2, @zk3]

    wait_until{ @connections.all? {|c| c.connected?} }

    @path = "shlock"
    @root_lock_path = "/_zklocking/#{@path}"
  end

  after do
    @connections.each { |c| c.close! }
    wait_until { @connections.all? { |c| !c.connected? } }
  end


  describe :SharedLocker do
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
          @write_lock_path = @zk.create("#{@root_lock_path}/#{ZK::Locker::EXCLUSIVE_LOCK_PREFIX}", '', :mode => :ephemeral_sequential)
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
          @write_lock_path = @zk.create("#{@root_lock_path}/#{ZK::Locker::EXCLUSIVE_LOCK_PREFIX}", '', :mode => :ephemeral_sequential)
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
  end   # SharedLocker

  describe :ExclusiveLocker do
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
  end   # WriteLocker

  describe 'read/write interaction' do
    before do
      @sh_lock = ZK::Locker.shared_locker(@zk, @path)
      @ex_lock = ZK::Locker.exclusive_locker(@zk2, @path)
    end

    describe 'shared lock acquired first' do
      it %[should block exclusive locks from acquiring until released] do
        q1 = Queue.new
        q2 = Queue.new

        th1 = Thread.new do
          @sh_lock.with_lock do
            q1.enq(:got_lock)
            Thread.current[:got_lock] = true
            q2.pop
          end
        end

        th2 = Thread.new do
          q1.pop # wait for th1 to get the shared lock

          Thread.current[:acquiring_lock] = true

          @ex_lock.with_lock do
            Thread.current[:got_lock] = true
          end
        end

        th1.join_until { th1[:got_lock] }
        th1[:got_lock].should be_true

        th2.join_until { th2[:acquiring_lock] }
        th2[:acquiring_lock].should be_true

        q2.num_waiting.should > 0
        q2.enq(:release)

        th1.join_until { q2.size == 0 }
        q2.size.should == 0

        th1.join(2).should == th1

        th2.join_until { th2[:got_lock] }
        th2[:got_lock].should be_true

        th2.join(2).should == th2
      end
    end

    describe 'exclusive lock acquired first' do
      it %[should block shared lock from acquiring until released] do
        # same test as above but with the thread's locks switched, 
        # th1 is the exclusive locker

        q1 = Queue.new
        q2 = Queue.new

        th1 = Thread.new do
          @ex_lock.with_lock do
            q1.enq(:got_lock)
            Thread.current[:got_lock] = true
            q2.pop
          end
        end

        th2 = Thread.new do
          q1.pop # wait for th1 to get the shared lock

          Thread.current[:acquiring_lock] = true

          @sh_lock.with_lock do
            Thread.current[:got_lock] = true
          end
        end

        th1.join_until { th1[:got_lock] }
        th1[:got_lock].should be_true

        th2.join_until { th2[:acquiring_lock] }
        th2[:acquiring_lock].should be_true

        q2.num_waiting.should > 0
        q2.enq(:release)

        th1.join_until { q2.size == 0 }
        q2.size.should == 0

        th1.join(2).should == th1

        th2.join_until { th2[:got_lock] }
        th2[:got_lock].should be_true

        th2.join(2).should == th2
      end
    end

    describe 'shared-exclusive-shared' do
      before do
        @zk3.should_not be_nil
        @sh_lock2 = ZK::Locker.shared_locker(@zk3, @path) 
      end

      it %[should act something like a queue] do
        @array = []

        @sh_lock.lock!.should be_true
        @sh_lock.should be_locked

        ex_th = Thread.new do
          begin
            @ex_lock.lock!(true)  # blocking lock
            Thread.current[:got_lock] = true
            @array << :ex_lock
          ensure
            @ex_lock.unlock!
          end
        end

        ex_th.join_until { @ex_lock.waiting? }
        @ex_lock.should be_waiting
        @ex_lock.should_not be_locked

        # this is the important one, does the second shared lock get blocked by
        # the exclusive lock
        @sh_lock2.lock!.should_not be_true

        sh2_th = Thread.new do
          begin
            @sh_lock2.lock!(true)
            Thread.current[:got_lock] = true
            @array << :sh_lock2
          ensure
            @sh_lock2.unlock!
          end
        end

        sh2_th.join_until { @sh_lock2.waiting? }
        @sh_lock2.should be_waiting

        @sh_lock.unlock!.should be_true

        ex_th.join_until { ex_th[:got_lock] }
        ex_th[:got_lock].should be_true

        sh2_th.join_until { sh2_th[:got_lock] }
        sh2_th[:got_lock].should be_true

        @array.length.should == 2
        @array.should == [:ex_lock, :sh_lock2]
      end
    end
  end
end

