require 'spec_helper'

# this is a remnant of the old Locker class, but a good test of what's expected
# from ZK::Client#locker
#
describe 'ZK::Client#locker' do
  include_context 'connection opts'

  before(:each) do
    @zk = ZK.new("localhost:#{ZK.test_port}", connection_opts)
    @zk2 = ZK.new("localhost:#{ZK.test_port}", connection_opts)
    @zk3 = ZK.new("localhost:#{ZK.test_port}", connection_opts)
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

shared_examples_for 'SharedLocker' do
  before do
    @shared_locker  = ZK::Locker.shared_locker(zk, path)
    @shared_locker2 = ZK::Locker.shared_locker(zk2, path)
  end

  describe :assert! do
    it %[should raise LockAssertionFailedError if its connection is no longer connected?] do
      zk.close!
      lambda { @shared_locker.assert! }.should raise_error(ZK::Exceptions::LockAssertionFailedError)
    end

    it %[should raise LockAssertionFailedError if locked? is false] do
      @shared_locker.should_not be_locked
      lambda { @shared_locker.assert! }.should raise_error(ZK::Exceptions::LockAssertionFailedError)
    end

    it %[should raise LockAssertionFailedError lock_path does not exist] do
      @shared_locker.lock!
      lambda { @shared_locker.assert! }.should_not raise_error

      zk.delete(@shared_locker.lock_path)
      lambda { @shared_locker.assert! }.should raise_error(ZK::Exceptions::LockAssertionFailedError)
    end

    it %[should raise LockAssertionFailedError if there is an exclusive lock with a number lower than ours] do
      # this should *really* never happen
      @shared_locker.lock!.should be_true
      shl_path = @shared_locker.lock_path

      @shared_locker2.lock!.should be_true

      @shared_locker.unlock!.should be_true
      @shared_locker.should_not be_locked

      zk.exists?(shl_path).should be_false

      @shared_locker2.lock_path.should_not == shl_path

      # convert the first shared lock path into a exclusive one

      exl_path = shl_path.sub(%r%/sh(\d+)\Z%, '/ex\1')

      zk.create(exl_path, :ephemeral => true)

      lambda { @shared_locker2.assert! }.should raise_error(ZK::Exceptions::LockAssertionFailedError)
    end
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
        zk.mkdir_p(root_lock_path)
        @write_lock_path = zk.create("#{root_lock_path}/#{ZK::Locker::EXCLUSIVE_LOCK_PREFIX}", '', :mode => :ephemeral_sequential)
        @rval = @shared_locker.lock!
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
        zk.mkdir_p(root_lock_path)
        @write_lock_path = zk.create("#{root_lock_path}/#{ZK::Locker::EXCLUSIVE_LOCK_PREFIX}", '', :mode => :ephemeral_sequential)
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

        zk.delete(@write_lock_path)

        th.join(2)

        wait_until(2) { !ary.empty? }
        ary.length.should == 1

        @shared_locker.should be_locked
      end
    end
  end
end   # SharedLocker

shared_examples_for 'ExclusiveLocker' do
  before do
    @ex_locker = ZK::Locker.exclusive_locker(zk, path)
    @ex_locker2 = ZK::Locker.exclusive_locker(zk2, path)
  end

  describe :assert! do
    it %[should raise LockAssertionFailedError if its connection is no longer connected?] do
      zk.close!
      lambda { @ex_locker.assert! }.should raise_error(ZK::Exceptions::LockAssertionFailedError)
    end

    it %[should raise LockAssertionFailedError if locked? is false] do
      @ex_locker.should_not be_locked
      lambda { @ex_locker.assert! }.should raise_error(ZK::Exceptions::LockAssertionFailedError)
    end

    it %[should raise LockAssertionFailedError lock_path does not exist] do
      @ex_locker.lock!
      lambda { @ex_locker.assert! }.should_not raise_error

      zk.delete(@ex_locker.lock_path)
      lambda { @ex_locker.assert! }.should raise_error(ZK::Exceptions::LockAssertionFailedError)
    end

    it %[should raise LockAssertionFailedError if there is an exclusive lock with a number lower than ours] do
      # this should *really* never happen
      @ex_locker.lock!.should be_true
      exl_path = @ex_locker.lock_path

      th = Thread.new do
        @ex_locker2.lock!(true)
      end

      wait_until { th.status == 'sleep' }

      @ex_locker.unlock!.should be_true
      @ex_locker.should_not be_locked
      zk.exists?(exl_path).should be_false

      th.join(5).should == th

      @ex_locker2.lock_path.should_not == exl_path

      zk.create(exl_path, :ephemeral => true)

      lambda { @ex_locker2.assert! }.should raise_error(ZK::Exceptions::LockAssertionFailedError)
    end
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
        zk.mkdir_p(root_lock_path)
        @read_lock_path = zk.create('/_zklocking/shlock/read', '', :mode => :ephemeral_sequential)
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

        zk.delete(@read_lock_path)

        th.join(2)

        ary.length.should == 1
        @ex_locker.should be_locked
      end
    end

  end
end # ExclusiveLocker

shared_examples_for 'shared-exclusive interaction' do
  before do
    @sh_lock = ZK::Locker.shared_locker(zk, path)
    @ex_lock = ZK::Locker.exclusive_locker(zk2, path)
  end

  describe 'shared lock acquired first' do
    it %[should block exclusive locks from acquiring until released] do
      @sh_lock.lock!.should be_true
      @ex_lock.lock!.should be_false

      mutex = Monitor.new
      cond = mutex.new_cond
      
      th = Thread.new do
        logger.debug { "@ex_lock trying to acquire acquire lock" }
        @ex_lock.with_lock do
          th[:got_lock] = @ex_lock.locked?
          logger.debug { "@ex_lock.locked? #{@ex_lock.locked?}" }

          mutex.synchronize do
            cond.broadcast
          end
        end
      end

      mutex.synchronize do
        logger.debug { "unlocking the shared lock" }
        @sh_lock.unlock!.should be_true
        cond.wait_until { th[:got_lock] }   # make sure they actually received the lock (avoid race)
        th[:got_lock].should be_true
        logger.debug { "ok, they got the lock" }
      end

      th.join(5).should == th

      logger.debug { "thread joined, exclusive lock should be releasd" }

      @ex_lock.should_not be_locked
    end
  end

  describe 'exclusive lock acquired first' do
    it %[should block shared lock from acquiring until released] do
      @ex_lock.lock!.should be_true
      @sh_lock.lock!.should be_false

      mutex = Monitor.new
      cond = mutex.new_cond
      
      th = Thread.new do
        logger.debug { "@ex_lock trying to acquire acquire lock" }
        @sh_lock.with_lock do
          th[:got_lock] = @sh_lock.locked?
          logger.debug { "@sh_lock.locked? #{@sh_lock.locked?}" }

          mutex.synchronize do
            cond.broadcast
          end
        end
      end

      mutex.synchronize do
        logger.debug { "unlocking the shared lock" }
        @ex_lock.unlock!.should be_true
        cond.wait_until { th[:got_lock] }   # make sure they actually received the lock (avoid race)
        th[:got_lock].should be_true
        logger.debug { "ok, they got the lock" }
      end

      th.join(5).should == th

      logger.debug { "thread joined, exclusive lock should be releasd" }

      @sh_lock.should_not be_locked
    end
  end

  describe 'shared-exclusive-shared' do
    before do
      zk3.should_not be_nil
      @sh_lock2 = ZK::Locker.shared_locker(zk3, path) 
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
end # shared-exclusive interaction

describe ZK::Locker do
  include_context 'connection opts'

  let(:zk)  { ZK.new("localhost:#{ZK.test_port}", connection_opts) }
  let(:zk2) { ZK.new("localhost:#{ZK.test_port}", connection_opts) }
  let(:zk3) { ZK.new("localhost:#{ZK.test_port}", connection_opts) }

  let(:connections) { [zk, zk2, zk3] }

  let(:path) { "shlock" }
  let(:root_lock_path) { "#{ZK::Locker.default_root_lock_node}/#{path}" }

  before do
    wait_until{ connections.all?(&:connected?) }
    zk.rm_rf(ZK::Locker.default_root_lock_node)
  end

  after do
    connections.each { |c| c.close! }
    wait_until { !connections.any?(&:connected?) }
    ZK.open("localhost:#{ZK.test_port}") { |z| z.rm_rf(ZK::Locker.default_root_lock_node) }
  end

  it_should_behave_like 'SharedLocker'
  it_should_behave_like 'ExclusiveLocker'
  it_should_behave_like 'shared-exclusive interaction'
end # ZK::Locker

describe ZK::Locker, :chrooted => true do
  include_context 'connection opts'

  let(:chroot_path) { '/_zk_chroot_' }

  let(:zk)  { ZK.new("localhost:#{ZK.test_port}#{chroot_path}", connection_opts) }

  describe 'when the chroot exists' do
    let(:zk2) { ZK.new("localhost:#{ZK.test_port}#{chroot_path}", connection_opts) }
    let(:zk3) { ZK.new("localhost:#{ZK.test_port}#{chroot_path}", connection_opts) }

    let(:connections) { [zk, zk2, zk3] }

    let(:path) { "shlock" }
    let(:root_lock_path) { "#{ZK::Locker.default_root_lock_node}/#{path}" }

    before do
      ZK.open("localhost:#{ZK.test_port}") do |zk|
        zk.mkdir_p(chroot_path)
      end

      wait_until{ connections.all?(&:connected?) }
    end

    after do
      connections.each { |c| c.close! }
      wait_until { !connections.any?(&:connected?) }

      ZK.open("localhost:#{ZK.test_port}") do |zk|
        zk.rm_rf(chroot_path)
      end
    end

    it_should_behave_like 'SharedLocker'
    it_should_behave_like 'ExclusiveLocker'
    it_should_behave_like 'shared-exclusive interaction'
  end
end


