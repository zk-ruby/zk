require 'spec_helper'

shared_examples_for 'ZK::Locker::SharedLocker' do
  let(:locker)  { ZK::Locker::SharedLocker.new(zk, path) }
  let(:locker2) { ZK::Locker::SharedLocker.new(zk2, path) }

  describe :assert! do
    it_should_behave_like 'LockerBase#assert!'

    it %[should raise LockAssertionFailedError if there is an exclusive lock with a number lower than ours] do
      # this should *really* never happen
      locker.lock.should be_true
      shl_path = locker.lock_path

      locker2.lock.should be_true

      locker.unlock.should be_true
      locker.should_not be_locked

      zk.exists?(shl_path).should be_false

      locker2.lock_path.should_not == shl_path

      # convert the first shared lock path into a exclusive one

      exl_path = shl_path.sub(%r%/sh(\d+)\Z%, '/ex\1')

      zk.create(exl_path, :ephemeral => true)

      lambda { locker2.assert! }.should raise_error(ZK::Exceptions::LockAssertionFailedError)
    end
  end

  describe :acquirable? do
    describe %[with default options] do
      it %[should work if the lock root doesn't exist] do
        zk.rm_rf(ZK::Locker.default_root_lock_node)
        locker.should be_acquirable
      end

      it %[should check local state of lockedness] do
        locker.lock.should be_true
        locker.should be_acquirable
      end

      it %[should check if any participants would prevent us from acquiring the lock] do
        ex_lock = ZK::Locker.exclusive_locker(zk, path)
        ex_lock.lock.should be_true
        locker.should_not be_acquirable
      end
    end
  end

  describe :lock do
    describe 'non-blocking success' do
      before do
        @rval   = locker.lock
        @rval2  = locker2.lock
      end

      it %[should acquire the first lock] do
        @rval.should be_true
        locker.should be_locked
      end

      it %[should acquire the second lock] do
        @rval2.should be_true
        locker2.should be_locked
      end
    end

    describe 'non-blocking failure' do
      before do
        zk.mkdir_p(root_lock_path)
        @write_lock_path = zk.create("#{root_lock_path}/#{ZK::Locker::EXCLUSIVE_LOCK_PREFIX}", '', :mode => :ephemeral_sequential)
        @rval = locker.lock
      end

      it %[should return false] do
        @rval.should be_false
      end

      it %[should not be locked] do
        locker.should_not be_locked
      end
    end

    context do
      before do
        zk.mkdir_p(root_lock_path)
        @write_lock_path = zk.create("#{root_lock_path}/#{ZK::Locker::EXCLUSIVE_LOCK_PREFIX}", '', :mode => :ephemeral_sequential)
        @exc = nil
      end

      describe 'blocking success' do
        it %[should acquire the lock after the write lock is released old-style] do
          ary = []

          locker.lock.should be_false

          th = Thread.new do
            locker.lock(true)
            ary << :locked
          end

          locker.wait_until_blocked(5)
          locker.should be_waiting
          locker.should_not be_locked
          ary.should be_empty

          zk.delete(@write_lock_path)

          th.join(2).should == th

          ary.should_not be_empty
          ary.length.should == 1

          locker.should be_locked
        end

        it %[should acquire the lock after the write lock is released new-style] do
          ary = []

          locker.lock.should be_false

          th = Thread.new do
            locker.lock(:wait => true)
            ary << :locked
          end

          locker.wait_until_blocked(5)
          locker.should be_waiting
          locker.should_not be_locked
          ary.should be_empty

          zk.delete(@write_lock_path)

          th.join(2).should == th

          ary.should_not be_empty
          ary.length.should == 1

          locker.should be_locked
        end
      end

      describe 'blocking timeout' do
        it %[should raise LockWaitTimeoutError] do
          ary = []

          write_lock_dir = File.dirname(@write_lock_path)

          zk.children(write_lock_dir).length.should == 1

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
          locker.should be_waiting
          locker.should_not be_locked
          ary.should be_empty

          th.join(2).should == th

          zk.children(write_lock_dir).length.should == 1

          ary.should be_empty
          @exc.should be_kind_of(ZK::Exceptions::LockWaitTimeoutError)
        end

      end
    end # context
  end # lock

  it_should_behave_like 'LockerBase#unlock'
end   # SharedLocker


describe do
  include_context 'locker non-chrooted'

  it_should_behave_like 'ZK::Locker::SharedLocker'
end

describe :chrooted => true do
  include_context 'locker chrooted'

  it_should_behave_like 'ZK::Locker::SharedLocker'
end

