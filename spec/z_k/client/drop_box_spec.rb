require 'spec_helper'

module ZK
  module Client
    describe 'ZK::Client::DropBox' do
      let(:drop_box) { DropBox.new }

      after do
        DropBox.remove_current
      end

      it %[should start out with an undefined value] do
        drop_box.value.should == DropBox::UNDEFINED
      end

      it %[should block the caller waiting for a response] do
        @rv = nil

        th1 = Thread.new do
          Thread.current.abort_on_exception = true
          @rv = drop_box.pop
        end

        wait_until(2) { th1.status == 'sleep' }

        th1.status.should == 'sleep'

        th2 = Thread.new do
          drop_box.push :result
        end

        th2.join(2).should == th2
        th1.join(2).should == th1

        @rv.should == :result
      end

      describe :oh_noes! do
        let(:error_class) { SpecialHappyFuntimeError }
        let(:error_msg)   { 'this is a unique message' }

        it %[should wake the caller by raising the exception class and message given] do
          drop_box.should_not be_done # sanity check

          th1 = Thread.new do
            drop_box.pop
          end

          wait_until(2) { th1.status == 'sleep' }

          th1.status.should == 'sleep'

          drop_box.oh_noes!(error_class, error_msg).should_not be_nil

          lambda { th1.join(2) }.should raise_error(error_class, error_msg)

          drop_box.should be_done
        end
      end

      describe :done? do
        it %[should be done if the value is defined] do
          drop_box.should_not be_done
          drop_box.push :defined
          drop_box.should be_done
        end

        it %[should not be done once cleared] do
          drop_box.push :defined
          drop_box.should be_done
          drop_box.clear
          drop_box.should_not be_done
        end
      end

      describe :with_current do
        it %[should clear the current thread's drop_box once the block exits] do
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

