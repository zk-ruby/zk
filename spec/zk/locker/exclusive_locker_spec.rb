require 'spec_helper'

shared_examples_for 'ZK::Locker::ExclusiveLocker' do
  let(:ex_locker) { ZK::Locker.exclusive_locker(zk, path) }
  let(:ex_locker2) { ZK::Locker.exclusive_locker(zk2, path) }

  describe :assert! do
    it %[should raise LockAssertionFailedError if its connection is no longer connected?] do
      zk.close!
      lambda { ex_locker.assert! }.should raise_error(ZK::Exceptions::LockAssertionFailedError)
    end

    it %[should raise LockAssertionFailedError if locked? is false] do
      ex_locker.should_not be_locked
      lambda { ex_locker.assert! }.should raise_error(ZK::Exceptions::LockAssertionFailedError)
    end

    it %[should raise LockAssertionFailedError lock_path does not exist] do
      ex_locker.lock
      lambda { ex_locker.assert! }.should_not raise_error

      zk.delete(ex_locker.lock_path)
      lambda { ex_locker.assert! }.should raise_error(ZK::Exceptions::LockAssertionFailedError)
    end

    it %[should raise LockAssertionFailedError if there is an exclusive lock with a number lower than ours] do
      # this should *really* never happen
      
      rlp = ex_locker.root_lock_path

      zk.mkdir_p(rlp)

      bogus_path = zk.create("#{rlp}/#{ZK::Locker::EXCLUSIVE_LOCK_PREFIX}", :sequential => true, :ephemeral => true)

      th = Thread.new do
        ex_locker2.lock(true)
      end

      logger.debug { "calling wait_until_blocked" }
      ex_locker2.wait_until_blocked(2)
      ex_locker2.should be_waiting

      wait_until { zk.exists?(ex_locker2.lock_path) }

      zk.exists?(ex_locker2.lock_path).should be_true

      zk.delete(bogus_path)

      th.join(5).should == th

      ex_locker2.lock_path.should_not == bogus_path

      zk.create(bogus_path, :ephemeral => true)

      lambda { ex_locker2.assert! }.should raise_error(ZK::Exceptions::LockAssertionFailedError)
    end
  end

  describe :acquirable? do
    it %[should work if the lock root doesn't exist] do
      zk.rm_rf(ZK::Locker.default_root_lock_node)
      ex_locker.should be_acquirable
    end

    it %[should check local state of lockedness] do
      ex_locker.lock.should be_true
      ex_locker.should be_acquirable
    end

    it %[should check if any participants would prevent us from acquiring the lock] do
      ex_locker.lock.should be_true
      ex_locker2.should_not be_acquirable
    end
  end

  describe :lock do
    describe 'non-blocking' do
      before do
        @rval = ex_locker.lock
        @rval2 = ex_locker2.lock
      end

      it %[should acquire the first lock] do
        @rval.should be_true
      end

      it %[should not acquire the second lock] do
        @rval2.should be_false
      end

      it %[should acquire the second lock after the first lock is released] do
        ex_locker.unlock.should be_true
        ex_locker2.lock.should be_true
      end
    end

    describe 'blocking' do
      before do
        zk.mkdir_p(root_lock_path)
      end

      it %[should block waiting for the lock] do
        ary = []
        read_lock_path = zk.create("/_zklocking/#{path}/read", '', :mode => :ephemeral_sequential)

        ex_locker.lock.should be_false

        th = Thread.new do
          ex_locker.lock(true)
          ary << :locked
        end

        ex_locker.wait_until_blocked(5)
      
        ary.should be_empty
        ex_locker.should_not be_locked

        zk.delete(read_lock_path)

        th.join(2).should == th

        ary.length.should == 1
        ex_locker.should be_locked
      end
    end # blocking
  end # lock
end # ExclusiveLocker

describe do
  include_context 'locker non-chrooted'
  it_should_behave_like 'ZK::Locker::ExclusiveLocker'
end

describe :chrooted => true do
  include_context 'locker chrooted'
  it_should_behave_like 'ZK::Locker::ExclusiveLocker'
end

