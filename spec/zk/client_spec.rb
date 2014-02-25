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

        @zk.should be_kind_of(ZK::Client::Threaded) # yeah yeah, just be sure

        shutdown_thread = nil

        @zk.defer do
          shutdown_thread = @zk.close!
        end

        wait_while { shutdown_thread.nil? }

        shutdown_thread.should_not be_nil
        shutdown_thread.should be_kind_of(Thread)

        shutdown_thread.join(5).should == shutdown_thread

        wait_until(5) { @zk.closed? }.should be_true
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
      @zk.connected?.should == true

      @zk.close!

      @zk.connected?.should == false

      @zk.reopen

      @zk.connected?.should == true
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

      @zk.should_not be_connected

      th = Thread.new do
        @zk.stat('/path/to/blah', :retry_duration => 30)
      end

      th.run

      @zk.connect
      th.join(5).should == th
    end

    it %[barfs if the connection is closed before the connected event is received] do
      @zk.should_not be_connected

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

      th.join(5).should == th

      exc.should_not be_nil
      exc.should be_kind_of(ZK::Exceptions::Retryable)
    end

    it %[should barf if the timeout expires] do
      @zk.should_not be_connected

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

      th.join(5).should == th

      exc.should_not be_nil
      exc.should be_kind_of(ZK::Exceptions::Retryable)
    end
  end
end # ZK::Client::Threaded

