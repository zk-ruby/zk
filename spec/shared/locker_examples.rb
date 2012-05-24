# basic shared exmples for locker specs (both exclusive and shared)

# these assume they're being executed in the 'locker chrooted' or 'locker
# non-chrooted' contexts
#
shared_examples_for 'LockerBase#assert!' do
  it %[should raise LockAssertionFailedError if its connection is no longer connected?] do
    zk.close!
    lambda { locker.assert! }.should raise_error(ZK::Exceptions::LockAssertionFailedError)
  end

  it %[should raise LockAssertionFailedError if locked? is false] do
    locker.should_not be_locked
    lambda { locker.assert! }.should raise_error(ZK::Exceptions::LockAssertionFailedError)
  end

  it %[should raise LockAssertionFailedError lock_path does not exist] do
    locker.lock
    lambda { locker.assert! }.should_not raise_error

    zk.delete(locker.lock_path)
    lambda { locker.assert! }.should raise_error(ZK::Exceptions::LockAssertionFailedError)
  end

  it %[should raise LockAssertionFailedError if our parent node's ctime is different than what we think it should be] do
    locker.lock.should be_true

    zk.rm_rf(File.dirname(locker.lock_path)) # remove the parent node
    zk.mkdir_p(locker.lock_path)

    lambda { locker.assert! }.should raise_error(ZK::Exceptions::LockAssertionFailedError)
  end
end

shared_examples_for 'LockerBase#unlock' do
  it %[should not delete a lock path it does not own] do
    locker.lock.should be_true

    zk.rm_rf(File.dirname(locker.lock_path)) # remove the parent node
    zk.mkdir_p(File.dirname(locker.lock_path))

    locker2.lock.should be_true

    locker2.lock_path.should == locker.lock_path

    lambda { locker2.assert! }.should_not raise_error

    lock_path = locker.lock_path

    locker.unlock.should be_false

    zk.stat(lock_path).should exist
  end
end

