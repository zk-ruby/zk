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
end # ZK::Client::Threaded

