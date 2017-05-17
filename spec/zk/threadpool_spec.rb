require 'spec_helper'

describe ZK::Threadpool do
  before do
    @threadpool = ZK::Threadpool.new
  end

  after do
    @threadpool.shutdown
  end

  describe :new do
    it %[should be running] do
      expect(@threadpool).to be_running
    end

    it %[should use the default size] do
      expect(@threadpool.size).to eq(ZK::Threadpool.default_size)
    end
  end

  describe :defer do
    it %[should run the given block on a thread in the threadpool] do
      @th = nil

      @threadpool.defer { @th = Thread.current }

      wait_until(2) { @th }

      expect(@th).not_to eq(Thread.current)
    end

    it %[should barf if the argument is not callable] do
      bad_obj = double(:not_callable)
      expect(bad_obj).not_to respond_to(:call)

      expect { @threadpool.defer(bad_obj) }.to raise_error(ArgumentError)
    end

    it %[should not barf if the threadpool is not running] do
      @threadpool.shutdown
      expect { @threadpool.defer { "hai!" } }.not_to raise_error
    end
  end

  describe :on_exception do
    it %[should register a callback that will be called if an exception is raised on the threadpool] do
      @ary = []

      @threadpool.on_exception { |exc| @ary << exc }

      @threadpool.defer { raise "ZOMG!" }

      wait_while(2) { @ary.empty? }

      expect(@ary.length).to eq(1)

      e = @ary.shift

      expect(e).to be_kind_of(RuntimeError)
      expect(e.message).to eq('ZOMG!')
    end
  end

  describe :shutdown do
    it %[should set running to false] do
      @threadpool.shutdown
      expect(@threadpool).not_to be_running
    end
  end

  describe :start! do
    it %[should be able to start a threadpool that had previously been shutdown (reuse)] do
      @threadpool.shutdown
      expect(@threadpool.start!).to be(true)

      expect(@threadpool).to be_running

      @rval = nil

      @threadpool.defer do
        @rval = true
      end

      wait_until(2) { @rval }
      expect(@rval).to be(true)
    end
  end

  describe :on_threadpool? do
    it %[should return true if we're currently executing on one of the threadpool threads] do
      @a = []
      @threadpool.defer { @a << @threadpool.on_threadpool? }

      wait_while(2) { @a.empty? }
      expect(@a).not_to be_empty

      expect(@a.first).to be(true)
    end
  end

  describe :pause_before_fork_in_parent do
    it %[should stop all running threads] do
      expect(@threadpool).to be_running
      expect(@threadpool).to be_alive
      @threadpool.pause_before_fork_in_parent

      expect(@threadpool).not_to be_alive
    end

    it %[should raise InvalidStateError if already paused] do
      @threadpool.pause_before_fork_in_parent
      expect { @threadpool.pause_before_fork_in_parent }.to raise_error(ZK::Exceptions::InvalidStateError)
    end
  end

  describe :resume_after_fork_in_parent do
    before do
      @threadpool.pause_before_fork_in_parent
    end

    it %[should start all threads running again] do
      @threadpool.resume_after_fork_in_parent
      expect(@threadpool).to be_alive
    end

    it %[should raise InvalidStateError if not in paused state] do
      @threadpool.shutdown
      expect { @threadpool.resume_after_fork_in_parent }.to raise_error(ZK::Exceptions::InvalidStateError)
    end

    it %[should run callbacks deferred while paused] do
      calls = []

      num = 5

      latch = Latch.new(num)

      num.times do |n|
        @threadpool.defer do
          calls << n
          latch.release
        end
      end

      @threadpool.resume_after_fork_in_parent

      latch.await(2)

      expect(calls).not_to be_empty
    end
  end
end

