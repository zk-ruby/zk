require 'spec_helper'

describe ZK::Client::Threaded do
  context do
    include_context 'threaded client connection'
    it_should_behave_like 'client'
  end

  describe :close! do
    describe 'from a threadpool thread' do
      include_context 'connection opts'

      before do
        @zk = ZK::Client::Threaded.new(*connection_args)
      end

      after do
        @zk.close! unless @zk.closed?
      end

      it %[should do the right thing and not fail] do
        # this is an extra special case where the user obviously hates us

        expect(@zk).to be_kind_of(ZK::Client::Threaded) # yeah yeah, just be sure

        shutdown_thread = nil

        @zk.defer do
          shutdown_thread = @zk.close!
        end

        wait_while { shutdown_thread.nil? }

        expect(shutdown_thread).not_to be_nil
        expect(shutdown_thread).to be_kind_of(Thread)

        expect(shutdown_thread.join(5)).to eq(shutdown_thread)

        expect(wait_until(5) { @zk.closed? }).to be(true)
      end
    end
  end

  describe :reopen do
    include_context 'connection opts'

    before do
      @zk = ZK::Client::Threaded.new(*connection_args)
    end

    after do
      @zk.close! unless @zk.closed?
    end

    it %[should say the client is connected after reopen] do
      expect(@zk.connected?).to eq(true)

      @zk.close!

      expect(@zk.connected?).to eq(false)

      @zk.reopen

      expect(@zk.connected?).to eq(true)
    end
  end

  describe :retry do
    include_context 'connection opts'

    before do
      @zk = ZK::Client::Threaded.new(connection_host, :reconect => false, :connect => false)
    end

    after do
      @zk.close! unless @zk.closed?
    end

    it %[should retry a Retryable operation] do
      # TODO: this is a terrible test. there is no way to guarantee that this
      #       has been retried. the join at the end should not raise an error

      expect(@zk).not_to be_connected

      th = Thread.new do
        @zk.stat('/path/to/blah', :retry_duration => 30)
      end

      th.run

      @zk.connect
      expect(th.join(5)).to eq(th)
    end

    it %[barfs if the connection is closed before the connected event is received] do
      expect(@zk).not_to be_connected

      exc = nil

      th = Thread.new do
        # this nonsense is because 1.8.7 is psychotic
        begin
          @zk.stat('/path/to/blah', :retry_duration => 300)
        rescue Exception
          exc = $!
        end
      end

      th.run

      @zk.close!

      expect(th.join(5)).to eq(th)

      expect(exc).not_to be_nil
      expect(exc).to be_kind_of(ZK::Exceptions::Retryable)
    end

    it %[should barf if the timeout expires] do
      expect(@zk).not_to be_connected

      exc = nil

      th = Thread.new do
        # this nonsense is because 1.8.7 is psychotic
        begin
          @zk.stat('/path/to/blah', :retry_duration => 0.001)
        rescue Exception
          exc = $!
        end
      end

      th.run

      expect(th.join(5)).to eq(th)

      expect(exc).not_to be_nil
      expect(exc).to be_kind_of(ZK::Exceptions::Retryable)
    end
  end
end # ZK::Client::Threaded

