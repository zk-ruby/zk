require 'spec_helper'

describe ZK::ThreadedCallback do
  before do
    @called = []
    @called.extend(MonitorMixin)
    @cond = @called.new_cond

    @callback = proc do |*a|
      @called.synchronize do
        @called << a
        @cond.broadcast
      end
    end

    @tcb = ZK::ThreadedCallback.new(@callback)
  end

  after do
    expect(@tcb.shutdown).to be(true)
  end

  it %[should have started the thread] do
    expect(@tcb).to be_alive
  end

  describe %[pausing for fork] do
    describe %[when running] do
      before do
        @tcb.pause_before_fork_in_parent
      end

      it %[should stop the thread] do
        expect(@tcb).not_to be_alive
      end

      it %[should allow calls] do
        expect { @tcb.call(:a) }.not_to raise_error
      end
    end

    describe %[when not running] do
      it %[should barf with InvalidStateError] do
        expect(@tcb.shutdown).to be(true)
        expect(@tcb).not_to be_alive
        expect { @tcb.pause_before_fork_in_parent }.to raise_error(ZK::Exceptions::InvalidStateError)
      end
    end
  end

  describe %[resuming] do
    describe %[after pause] do
      before do
        @tcb.pause_before_fork_in_parent
        expect(@tcb).not_to be_alive
      end

      it %[should deliver any calls on resume] do
        @tcb.call(:a)
        @tcb.call(:b)

        @tcb.resume_after_fork_in_parent

        start = Time.now

        wait_until { @called.length >= 2 }

        expect(@called.length).to be >= 2
      end
    end

    describe %[if not paused] do
      it %[should barf with InvalidStateError] do
        expect { @tcb.resume_after_fork_in_parent }.to raise_error(ZK::Exceptions::InvalidStateError)
      end
    end
  end
end
