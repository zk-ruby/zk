require 'spec_helper'

shared_examples_for 'ZK::Locker::ExclusiveLocker' do
  let(:locker) { ZK::Locker.exclusive_locker(zk, path) }
  let(:locker2) { ZK::Locker.exclusive_locker(zk2, path) }

  describe :assert! do
    it_should_behave_like 'LockerBase#assert!'

    it %[should raise LockAssertionFailedError if there is an exclusive lock with a number lower than ours] do
      # this should *really* never happen
      
      rlp = locker.root_lock_path

      zk.mkdir_p(rlp)

      bogus_path = zk.create("#{rlp}/#{ZK::Locker::EXCLUSIVE_LOCK_PREFIX}", :sequential => true, :ephemeral => true)
      logger.debug { "bogus_path: #{bogus_path.inspect}" } 

      th = Thread.new do
        locker.lock(true)
      end

      th.run

      logger.debug { "calling wait_until_blocked" }
      proc { locker.wait_until_blocked(5) }.should_not raise_error
      logger.debug { "wait_until_blocked returned" }
      locker.should be_waiting

      wait_until { zk.exists?(locker.lock_path) }

      zk.exists?(locker.lock_path).should be_true

      zk.delete(bogus_path)

      th.join(5).should == th

      locker.lock_path.should_not == bogus_path

      zk.create(bogus_path, :ephemeral => true)

      lambda { locker.assert! }.should raise_error(ZK::Exceptions::LockAssertionFailedError)
    end
  end

  describe :acquirable? do
    it %[should work if the lock root doesn't exist] do
      zk.rm_rf(ZK::Locker.default_root_lock_node)
      locker.should be_acquirable
    end

    it %[should check local state of lockedness] do
      locker.lock.should be_true
      locker.should be_acquirable
    end

    it %[should check if any participants would prevent us from acquiring the lock] do
      locker.lock.should be_true
      locker2.should_not be_acquirable
    end
  end

  describe :lock do
    describe 'non-blocking' do
      before do
        @rval = locker.lock
        @rval2 = locker2.lock
      end

      it %[should acquire the first lock] do
        @rval.should be_true
      end

      it %[should not acquire the second lock] do
        @rval2.should be_false
      end

      it %[should acquire the second lock after the first lock is released] do
        locker.unlock.should be_true
        locker2.lock.should be_true
      end
    end

    describe 'blocking' do
      let(:lock_path_base) { File.join(ZK::Locker.default_root_lock_node, path) }
      let(:read_lock_path_template) { File.join(lock_path_base, ZK::Locker::SHARED_LOCK_PREFIX) }

      before do
        zk.mkdir_p(root_lock_path)
        @read_lock_path = zk.create(read_lock_path_template, '', :mode => :ephemeral_sequential)
        @exc = nil
      end

      it %[should block waiting for the lock with old style lock semantics] do
        ary = []

        locker.lock.should be_false

        th = Thread.new do
          locker.lock(true)
          ary << :locked
        end

        locker.wait_until_blocked(5)
      
        ary.should be_empty
        locker.should_not be_locked

        zk.delete(@read_lock_path)

        th.join(2).should == th

        ary.length.should == 1
        locker.should be_locked
      end

      it %[should block waiting for the lock with new style lock semantics] do
        ary = []

        locker.lock.should be_false

        th = Thread.new do
          locker.lock(:wait => true)
          ary << :locked
        end

        locker.wait_until_blocked(5)
      
        ary.should be_empty
        locker.should_not be_locked

        zk.delete(@read_lock_path)

        th.join(2).should == th

        ary.length.should == 1
        locker.should be_locked
      end

      it %[should time out waiting for the lock] do
        ary = []

        zk.children(lock_path_base).length.should == 1

        locker.lock.should be_false

        th = Thread.new do
          begin
            locker.lock(:wait => 0.01)
            ary << :locked
          rescue Exception => e
            @exc = e
          end
        end

        locker.wait_until_blocked(5)
      
        ary.should be_empty
        locker.should_not be_locked

        th.join(2).should == th

        zk.children(lock_path_base).length.should == 1

        ary.should be_empty
        @exc.should_not be_nil
        @exc.should be_kind_of(ZK::Exceptions::LockWaitTimeoutError)
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

