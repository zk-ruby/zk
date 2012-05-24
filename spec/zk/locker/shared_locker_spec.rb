require 'spec_helper'

shared_examples_for 'ZK::Locker::SharedLocker' do
  let(:shared_locker)  { ZK::Locker.shared_locker(zk, path) }
  let(:shared_locker2) { ZK::Locker.shared_locker(zk2, path) }

  describe :assert! do
    it %[should raise LockAssertionFailedError if its connection is no longer connected?] do
      zk.close!
      lambda { shared_locker.assert! }.should raise_error(ZK::Exceptions::LockAssertionFailedError)
    end

    it %[should raise LockAssertionFailedError if locked? is false] do
      shared_locker.should_not be_locked
      lambda { shared_locker.assert! }.should raise_error(ZK::Exceptions::LockAssertionFailedError)
    end

    it %[should raise LockAssertionFailedError lock_path does not exist] do
      shared_locker.lock
      lambda { shared_locker.assert! }.should_not raise_error

      zk.delete(shared_locker.lock_path)
      lambda { shared_locker.assert! }.should raise_error(ZK::Exceptions::LockAssertionFailedError)
    end

    it %[should raise LockAssertionFailedError if there is an exclusive lock with a number lower than ours] do
      # this should *really* never happen
      shared_locker.lock.should be_true
      shl_path = shared_locker.lock_path

      shared_locker2.lock.should be_true

      shared_locker.unlock.should be_true
      shared_locker.should_not be_locked

      zk.exists?(shl_path).should be_false

      shared_locker2.lock_path.should_not == shl_path

      # convert the first shared lock path into a exclusive one

      exl_path = shl_path.sub(%r%/sh(\d+)\Z%, '/ex\1')

      zk.create(exl_path, :ephemeral => true)

      lambda { shared_locker2.assert! }.should raise_error(ZK::Exceptions::LockAssertionFailedError)
    end
  end

  describe :acquirable? do
    describe %[with default options] do
      it %[should work if the lock root doesn't exist] do
        zk.rm_rf(ZK::Locker.default_root_lock_node)
        shared_locker.should be_acquirable
      end

      it %[should check local state of lockedness] do
        shared_locker.lock.should be_true
        shared_locker.should be_acquirable
      end

      it %[should check if any participants would prevent us from acquiring the lock] do
        ex_lock = ZK::Locker.exclusive_locker(zk, path)
        ex_lock.lock.should be_true
        shared_locker.should_not be_acquirable
      end
    end
  end

  describe :lock do
    describe 'non-blocking success' do
      before do
        @rval   = shared_locker.lock
        @rval2  = shared_locker2.lock
      end

      it %[should acquire the first lock] do
        @rval.should be_true
        shared_locker.should be_locked
      end

      it %[should acquire the second lock] do
        @rval2.should be_true
        shared_locker2.should be_locked
      end
    end

    describe 'non-blocking failure' do
      before do
        zk.mkdir_p(root_lock_path)
        @write_lock_path = zk.create("#{root_lock_path}/#{ZK::Locker::EXCLUSIVE_LOCK_PREFIX}", '', :mode => :ephemeral_sequential)
        @rval = shared_locker.lock
      end

      it %[should return false] do
        @rval.should be_false
      end

      it %[should not be locked] do
        shared_locker.should_not be_locked
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

        shared_locker.lock.should be_false

        th = Thread.new do
          shared_locker.lock(true)
          ary << :locked
        end

        shared_locker.wait_until_blocked(5)
        shared_locker.should be_waiting
        shared_locker.should_not be_locked
        ary.should be_empty

        zk.delete(@write_lock_path)

        th.join(2).should == th

        ary.should_not be_empty
        ary.length.should == 1

        shared_locker.should be_locked
      end
    end
  end # lock

  describe :unlock do
    it %[should not unlock a lock it does] do
    end
  end
end   # SharedLocker


describe do
  include_context 'locker non-chrooted'

  it_should_behave_like 'ZK::Locker::SharedLocker'
end

describe :chrooted => true do
  include_context 'locker chrooted'

  it_should_behave_like 'ZK::Locker::SharedLocker'
end

