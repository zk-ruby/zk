require 'spec_helper'

describe ZK::Client::Threaded do
  include_context 'threaded client connection'
  it_should_behave_like 'client'

  describe :close! do
    describe 'from a threadpool thread' do
      it %[should do the right thing and not fail] do
        # this is an extra special case where the user obviously hates us

        @zk.should be_kind_of(ZK::Client::Threaded) # yeah yeah, just be sure

        mutex = Mutex.new
        enter_cond = ConditionVariable.new
        exit_cond = ConditionVariable.new

        @zk.defer do
          mutex.synchronize do
#             logger.debug { "waiting for signal to enter" }
#             enter_cond.wait(mutex)
            begin
              @zk.close!
            ensure
              logger.debug { "signaling on exit" }
              exit_cond.signal
            end
          end
        end

        mutex.synchronize do
#           logger.debug { "signalling threadpool thread to exit" }
#           enter_cond.signal
          logger.debug { "waiting for exit" }
          exit_cond.wait(mutex)
        end

        wait_until { @zk.closed? }.should be_true 
      end
    end
  end
end

