require 'spec_helper'

shared_examples_for 'ZK::Locker::Semaphore' do
  let(:semaphore_size){ 2 }
  let(:locker)  { ZK::Locker::Semaphore.new(zk, path, semaphore_size) }
  let(:locker2) { ZK::Locker::Semaphore.new(zk2, path, semaphore_size) }
  let(:locker3) { ZK::Locker::Semaphore.new(zk3, path, semaphore_size) }

  describe :assert! do
    it_should_behave_like 'LockerBase#assert!'
  end

  context %[invalid semaphore_size] do
    let(:semaphore_size) { :boom }
    it 'should raise' do
      expect{ locker }.to raise_error(ZK::Exceptions::BadArguments)
    end
  end

  describe :acquirable? do
    describe %[with default options] do
      it %[should work if the lock root doesn't exist] do
        zk.rm_rf(ZK::Locker::Semaphore.default_root_node)
        expect(locker).to be_acquirable
      end

      it %[should check local state of lockedness] do
        expect(locker.lock).to be(true)
        expect(locker).to be_acquirable
      end

      it %[should check if any participants would prevent us from acquiring the lock] do
        expect(locker3.lock).to be(true)
        expect(locker).to be_acquirable # total locks given less than semaphore_size
        expect(locker2.lock).to be(true)
        expect(locker).not_to be_acquirable # total locks given equal to semaphore size
        locker3.unlock
        expect(locker).to be_acquirable # total locks given less than semaphore_size
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
        expect(@rval).to be(true)
        expect(locker).to be_locked
      end

      it %[should acquire the second lock] do
        expect(@rval2).to be(true)
        expect(locker2).to be_locked
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
        expect(@rval).to be(false)
      end

      it %[should not be locked] do
        expect(locker).not_to be_locked
      end

      it %[should not have a lock_path] do
        expect(locker.lock_path).to be_nil
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

          expect(locker.lock).to be(false)

          th = Thread.new do
            locker.lock(:wait => true)
            ary << :locked
          end

          locker.wait_until_blocked(5)
          expect(locker).to be_waiting
          expect(locker).not_to be_locked
          expect(ary).to be_empty

          zk.delete(@existing_locks.shuffle.first)

          expect(th.join(2)).to eq(th)

          expect(ary).not_to be_empty
          expect(ary.length).to eq(1)

          expect(locker).to be_locked
        end
      end

      describe 'blocking timeout' do
        it %[should raise LockWaitTimeoutError] do
          ary = []

          write_lock_dir = File.dirname(@existing_locks.first)

          expect(zk.children(write_lock_dir).length).to eq(semaphore_size)

          expect(locker.lock).to be(false)

          th = Thread.new do
            begin
              locker.lock(:wait => 0.01)
              ary << :locked
            rescue Exception => e
              @exc = e
            end
          end

          locker.wait_until_blocked(5)
          expect(locker).to be_waiting
          expect(locker).not_to be_locked
          expect(ary).to be_empty

          expect(th.join(2)).to eq(th)

          expect(zk.children(write_lock_dir).length).to eq(semaphore_size)

          expect(ary).to be_empty
          expect(@exc).to be_kind_of(ZK::Exceptions::LockWaitTimeoutError)
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
