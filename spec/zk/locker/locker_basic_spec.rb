require 'spec_helper'

# this is a remnant of the old Locker class, but a good test of what's expected
# from ZK::Client#locker
#
describe 'ZK::Client#locker' do
  include_context 'connection opts'

  before(:each) do
    @zk = ZK.new(*connection_args)
    @zk2 = ZK.new(*connection_args)
    @zk3 = ZK.new(*connection_args)
    @connections = [@zk, @zk2, @zk3]
    wait_until { @connections.all? { |c| c.connected? } }
    logger.debug { "all connections connected" }
    @path_to_lock = "/lock_tester"
  end

  after(:each) do
    @zk.close!
    @zk2.close!
    @zk3.close!
    wait_until { @connections.all? { |c| c.closed? } }
  end

  it "should be able to acquire the lock if no one else is locking it" do
    expect(@zk.locker(@path_to_lock).lock).to be(true)
  end

  it "should not be able to acquire the lock if someone else is locking it" do
    expect(@zk.locker(@path_to_lock).lock).to be(true)
    expect(@zk2.locker(@path_to_lock).lock).to be(false)
  end

  it "should assert properly if lock is acquired" do
    expect(@zk.locker(@path_to_lock).assert).to be(false)
    l = @zk2.locker(@path_to_lock)
    expect(l.lock).to be(true)
    expect(l.assert).to be(true)
  end

  it "should be able to acquire the lock after the first one releases it" do
    lock1 = @zk.locker(@path_to_lock)
    lock2 = @zk2.locker(@path_to_lock)

    expect(lock1.lock).to be(true)
    expect(lock2.lock).to be(false)
    lock1.unlock
    expect(lock2.lock).to be(true)
  end

  it "should be able to acquire the lock if the first locker goes away" do
    lock1 = @zk.locker(@path_to_lock)
    lock2 = @zk2.locker(@path_to_lock)

    expect(lock1.lock).to be(true)
    expect(lock2.lock).to be(false)
    @zk.close!
    expect(lock2.lock).to be(true)
  end

  it "should be able to handle multi part path locks" do
    expect(@zk.locker("my/multi/part/path").lock).to be(true)
  end

  describe :with_lock do
    # TODO: reorganize these tests so Convenience testing is done somewhere saner
    #
    # this tests ZK::Client::Conveniences, maybe shouldn't be *here*
    describe 'Client::Conveniences' do
      it %[should yield the lock instance to the block] do
        @zk.with_lock(@path_to_lock) do |lock|
          expect(lock).not_to be_nil
          expect(lock).to be_kind_of(ZK::Locker::LockerBase)
          expect { lock.assert! }.not_to raise_error
        end
      end

      it %[should yield a shared lock when :mode => shared given] do
        @zk.with_lock(@path_to_lock, :mode => :shared) do |lock|
          expect(lock).not_to be_nil
          expect(lock).to be_kind_of(ZK::Locker::SharedLocker)
          expect { lock.assert! }.not_to raise_error
        end
      end

      it %[should take a timeout] do
        first_lock = @zk.locker(@path_to_lock)
        expect(first_lock.lock).to be(true)

        thread = Thread.new do
          begin
            @zk.with_lock(@path_to_lock, :wait => 0.01) do |lock|
              raise "NO NO NO!! should not have called the block!!"
            end
          rescue Exception => e
            @exc = e
          end
        end

        expect(thread.join(2)).to eq(thread)
        expect(@exc).to be_kind_of(ZK::Exceptions::LockWaitTimeoutError)
      end
    end

    describe 'LockerBase' do
      it "should blocking lock" do
        array = []
        first_lock = @zk.locker("mylock")
        expect(first_lock.lock).to be(true)
        array << :first_lock

        thread = Thread.new do
          @zk.locker("mylock").with_lock do
            array << :second_lock
          end
          expect(array.length).to eq(2)
        end

        expect(array.length).to eq(1)
        first_lock.unlock
        thread.join(10)
        expect(array.length).to eq(2)
      end

      it %[should accept a :wait option] do
        array = []
        first_lock = @zk.locker("mylock")
        expect(first_lock.lock).to be(true)

        second_lock = @zk.locker("mylock")

        thread = Thread.new do
          begin
            second_lock.with_lock(:wait => 0.01) do
              array << :second_lock
            end
          rescue Exception => e
            @exc = e
          end
        end

        expect(array).to be_empty
        expect(thread.join(2)).to eq(thread)
        expect(@exc).not_to be_nil
        expect(@exc).to be_kind_of(ZK::Exceptions::LockWaitTimeoutError)
      end

      it "should interrupt a blocked lock" do
        first_lock = @zk.locker("mylock")
        expect(first_lock.lock).to be(true)

        second_lock = @zk.locker("mylock")
        thread = Thread.new do
          begin
            second_lock.with_lock do
              raise "NO NO NO!! should not have called the block!!"
            end
          rescue Exception => e
            @exc = e
          end
        end

        Thread.pass until second_lock.waiting?

        second_lock.interrupt!
        thread.join(2)
        expect(@exc).to be_kind_of(ZK::Exceptions::WakeUpException)
      end
    end
  end # with_lock
end


