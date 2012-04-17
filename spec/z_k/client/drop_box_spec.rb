require 'spec_helper'

module ZK
  module Client
    describe 'ZK::Client::DropBox' do
      let(:continuation) { DropBox.new }

      after do
        DropBox.remove_current
      end

      it %[should start out with an undefined value] do
        continuation.value.should == DropBox::UNDEFINED
      end

      it %[should block the caller waiting for a response] do
        @rv = nil

        th1 = Thread.new do
          Thread.current.abort_on_exception = true
          @rv = continuation.pop
        end

        wait_until(2) { th1.status == 'sleep' }

        th1.status.should == 'sleep'

        th2 = Thread.new do
          continuation.push :result
        end

        th2.join(2).should == th2
        th1.join(2).should == th1

        @rv.should == :result
      end

      it %[should be done if the value is defined] do
        continuation.should_not be_done
        continuation.push :defined
        continuation.should be_done
      end

      it %[should not be done once cleared] do
        continuation.push :defined
        continuation.should be_done
        continuation.clear
        continuation.should_not be_done
      end

      describe 'with_current' do
        it %[should clear the current thread's continuation once the block exits] do
          DropBox.with_current do |c|
            c.should_not be_done
            c.push 'yo_mama'
            c.should be_done
          end

          DropBox.current.should_not be_done
        end
      end

    end
  end
end

