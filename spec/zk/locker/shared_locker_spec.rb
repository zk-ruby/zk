require 'spec_helper'

shared_examples_for 'ZK::Locker::SharedLocker' do
  let(:locker)  { ZK::Locker::SharedLocker.new(zk, path) }
  let(:locker2) { ZK::Locker::SharedLocker.new(zk2, path) }

  describe :assert! do
    it_should_behave_like 'LockerBase#assert!'

    it %[should raise LockAssertionFailedError if there is an exclusive lock with a number lower than ours] do
      # this should *really* never happen
      expect(locker.lock).to be(true)
      shl_path = locker.lock_path

      expect(locker2.lock).to be(true)

      expect(locker.unlock).to be(true)
      expect(locker).not_to be_locked

      expect(zk.exists?(shl_path)).to be(false)

      expect(locker2.lock_path).not_to eq(shl_path)

      # convert the first shared lock path into a exclusive one

      exl_path = shl_path.sub(%r%/sh(\d+)\Z%, '/ex\1')

      zk.create(exl_path, :ephemeral => true)

      expect { locker2.assert! }.to raise_error(ZK::Exceptions::LockAssertionFailedError)
    end
  end

  describe :acquirable? do
    describe %[with default options] do
      it %[should work if the lock root doesn't exist] do
        zk.rm_rf(ZK::Locker.default_root_lock_node)
        expect(locker).to be_acquirable
      end

      it %[should check local state of lockedness] do
        expect(locker.lock).to be(true)
        expect(locker).to be_acquirable
      end

      it %[should check if any participants would prevent us from acquiring the lock] do
        ex_lock = ZK::Locker.exclusive_locker(zk, path)
        expect(ex_lock.lock).to be(true)
        expect(locker).not_to be_acquirable
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
        zk.mkdir_p(root_lock_path)
        @write_lock_path = zk.create("#{root_lock_path}/#{ZK::Locker::EXCLUSIVE_LOCK_PREFIX}", '', :mode => :ephemeral_sequential)
        @rval = locker.lock
      end

      it %[should return false] do
        expect(@rval).to be(false)
      end

      it %[should not be locked] do
        expect(locker).not_to be_locked
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

          expect(locker.lock).to be(false)

          th = Thread.new do
            locker.lock(true)
            ary << :locked
          end

          locker.wait_until_blocked(5)
          expect(locker).to be_waiting
          expect(locker).not_to be_locked
          expect(ary).to be_empty

          zk.delete(@write_lock_path)

          expect(th.join(2)).to eq(th)

          expect(ary).not_to be_empty
          expect(ary.length).to eq(1)

          expect(locker).to be_locked
        end

        it %[should acquire the lock after the write lock is released new-style] do
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

          zk.delete(@write_lock_path)

          expect(th.join(2)).to eq(th)

          expect(ary).not_to be_empty
          expect(ary.length).to eq(1)

          expect(locker).to be_locked
        end
      end

      describe 'blocking timeout' do
        it %[should raise LockWaitTimeoutError] do
          ary = []

          write_lock_dir = File.dirname(@write_lock_path)

          expect(zk.children(write_lock_dir).length).to eq(1)

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

          expect(zk.children(write_lock_dir).length).to eq(1)

          expect(ary).to be_empty
          expect(@exc).to be_kind_of(ZK::Exceptions::LockWaitTimeoutError)
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

