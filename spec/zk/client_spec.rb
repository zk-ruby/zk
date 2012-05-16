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

        @zk.defer do
          @zk.close!
        end

        wait_until(5) { @zk.closed? }.should be_true 
      end
    end
  end

  describe :reopen do
    include_context 'connection opts'

    before { @zk = ZK::Client::Threaded.new(*connection_args) }

    after  { @zk.close! if @zk and !@zk.closed? }

    it %[should get a new sesion id] do
      orig_id = @zk.session_id

      @zk.reopen
      @zk.should be_connected
      @zk.session_id.should_not == orig_id
    end
  end

end # ZK::Client::Threaded

