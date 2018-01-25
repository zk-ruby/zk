# basic shared exmples for locker specs (both exclusive and shared)

# these assume they're being executed in the 'locker chrooted' or 'locker
# non-chrooted' contexts
#
shared_examples_for 'LockerBase#assert!' do
  it %[should raise LockAssertionFailedError if its connection is no longer connected?] do
    zk.close!
    expect { locker.assert! }.to raise_error(ZK::Exceptions::LockAssertionFailedError)
  end

  it %[should raise LockAssertionFailedError if locked? is false] do
    expect(locker).not_to be_locked
    expect { locker.assert! }.to raise_error(ZK::Exceptions::LockAssertionFailedError)
  end

  it %[should raise LockAssertionFailedError lock_path does not exist] do
    locker.lock
    expect { locker.assert! }.not_to raise_error

    zk.delete(locker.lock_path)
    expect { locker.assert! }.to raise_error(ZK::Exceptions::LockAssertionFailedError)
  end

  it %[should raise LockAssertionFailedError if our parent node's ctime is different than what we think it should be] do
    expect(locker.lock).to be(true)

    zk.rm_rf(File.dirname(locker.lock_path)) # remove the parent node
    zk.mkdir_p(locker.lock_path)

    expect { locker.assert! }.to raise_error(ZK::Exceptions::LockAssertionFailedError)
  end
end

shared_examples_for 'LockerBase#unlock' do
  it %[should not delete a lock path it does not own] do
    expect(locker.lock).to be(true)

    zk.rm_rf(File.dirname(locker.lock_path)) # remove the parent node
    zk.mkdir_p(File.dirname(locker.lock_path))

    expect(locker2.lock).to be(true)

    expect(locker2.lock_path).to eq(locker.lock_path)

    expect { locker2.assert! }.not_to raise_error

    lock_path = locker.lock_path

    expect(locker.unlock).to be(false)

    expect(zk.stat(lock_path)).to exist
  end
end

