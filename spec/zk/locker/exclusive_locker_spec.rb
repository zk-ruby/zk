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
      expect { locker.wait_until_blocked(5) }.not_to raise_error
      logger.debug { "wait_until_blocked returned" }
      expect(locker).to be_waiting

      wait_until { zk.exists?(locker.lock_path) }

      expect(zk.exists?(locker.lock_path)).to be(true)

      zk.delete(bogus_path)

      expect(th.join(5)).to eq(th)

      expect(locker.lock_path).not_to eq(bogus_path)

      zk.create(bogus_path, :ephemeral => true)

      expect { locker.assert! }.to raise_error(ZK::Exceptions::LockAssertionFailedError)
    end
  end

  describe :acquirable? do
    it %[should work if the lock root doesn't exist] do
      zk.rm_rf(ZK::Locker.default_root_lock_node)
      expect(locker).to be_acquirable
    end

    it %[should check local state of lockedness] do
      expect(locker.lock).to be(true)
      expect(locker).to be_acquirable
    end

    it %[should check if any participants would prevent us from acquiring the lock] do
      expect(locker.lock).to be(true)
      expect(locker2).not_to be_acquirable
    end
  end

  describe :lock do
    describe 'non-blocking' do
      before do
        @rval = locker.lock
        @rval2 = locker2.lock
      end

      it %[should acquire the first lock] do
        expect(@rval).to be(true)
      end

      it %[should not acquire the second lock] do
        expect(@rval2).to be(false)
      end

      it %[should acquire the second lock after the first lock is released] do
        expect(locker.unlock).to be(true)
        expect(locker2.lock).to be(true)
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

        expect(locker.lock).to be(false)

        th = Thread.new do
          locker.lock(true)
          ary << :locked
        end

        locker.wait_until_blocked(5)

        expect(ary).to be_empty
        expect(locker).not_to be_locked

        zk.delete(@read_lock_path)

        expect(th.join(2)).to eq(th)

        expect(ary.length).to eq(1)
        expect(locker).to be_locked
      end

      it %[should block waiting for the lock with new style lock semantics] do
        ary = []

        expect(locker.lock).to be(false)

        th = Thread.new do
          locker.lock(:wait => true)
          ary << :locked
        end

        locker.wait_until_blocked(5)

        expect(ary).to be_empty
        expect(locker).not_to be_locked

        zk.delete(@read_lock_path)

        expect(th.join(2)).to eq(th)

        expect(ary.length).to eq(1)
        expect(locker).to be_locked
      end

      it %[should time out waiting for the lock] do
        ary = []

        expect(zk.children(lock_path_base).length).to eq(1)

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

        expect(ary).to be_empty
        expect(locker).not_to be_locked

        expect(th.join(2)).to eq(th)

        expect(zk.children(lock_path_base).length).to eq(1)

        expect(ary).to be_empty
        expect(@exc).not_to be_nil
        expect(@exc).to be_kind_of(ZK::Exceptions::LockWaitTimeoutError)
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

