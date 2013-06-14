require 'spec_helper'

shared_examples_for 'ZK::Locker::Semaphore' do
  let(:semaphore_size){ 2 }
  let(:locker)  { ZK::Locker::Semaphore.new(zk, path, semaphore_size) }
  let(:locker2) { ZK::Locker::Semaphore.new(zk2, path, semaphore_size) }
  let(:locker3) { ZK::Locker::Semaphore.new(zk3, path, semaphore_size) }

  describe :assert! do
    it_should_behave_like 'LockerBase#assert!'
  end

  describe :acquirable? do
    describe %[with default options] do
      it %[should work if the lock root doesn't exist] do
        zk.rm_rf(ZK::Locker::Semaphore.default_root_node)
        locker.should be_acquirable
      end

      it %[should check local state of lockedness] do
        locker.lock.should be_true
        locker.should be_acquirable
      end

      it %[should check if any participants would prevent us from acquiring the lock] do
        locker3.lock.should be_true
        locker.should be_acquirable # total locks given less than semaphore_size
        locker2.lock.should be_true
        locker.should_not be_acquirable # total locks given equal to semaphore size
        locker3.unlock
        locker.should be_acquirable # total locks given less than semaphore_size
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
        zk.mkdir_p(semaphore_root_path)
        semaphore_size.times do
          zk.create("#{semaphore_root_path}/#{ZK::Locker::SEMAPHORE_LOCK_PREFIX}", '', :mode => :ephemeral_sequential)
        end
        @rval = locker.lock
      end

      it %[should return false] do
        @rval.should be_false
      end

      it %[should not be locked] do
        locker.should_not be_locked
      end

      it %[should not have a lock_path] do
        locker.lock_path.should be_nil
      end
    end

    context do
      before do
        zk.mkdir_p(semaphore_root_path)
        @existing_locks = semaphore_size.times.map do
          zk.create("#{semaphore_root_path}/#{ZK::Locker::SEMAPHORE_LOCK_PREFIX}", '', :mode => :ephemeral_sequential)
        end
        @exc = nil
      end

      describe 'blocking success' do

        it %[should acquire the lock after the write lock is released] do
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

          zk.delete(@existing_locks.shuffle.first)

          th.join(2).should == th

          ary.should_not be_empty
          ary.length.should == 1

          locker.should be_locked
        end
      end

      describe 'blocking timeout' do
        it %[should raise LockWaitTimeoutError] do
          ary = []

          write_lock_dir = File.dirname(@existing_locks.first)

          zk.children(write_lock_dir).length.should == semaphore_size

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

          zk.children(write_lock_dir).length.should == semaphore_size

          ary.should be_empty
          @exc.should be_kind_of(ZK::Exceptions::LockWaitTimeoutError)
        end

      end
    end # context
  end # lock

  describe :unlock do
    it_should_behave_like 'LockerBase#unlock'
  end
end   # SharedLocker


describe do
  include_context 'locker non-chrooted'

  it_should_behave_like 'ZK::Locker::Semaphore'
end

describe :chrooted => true do
  include_context 'locker chrooted'

  it_should_behave_like 'ZK::Locker::Semaphore'
end
