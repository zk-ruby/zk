require 'spec_helper'

module ZK
  describe 'Extensions' do
    describe 'Exception#to_std_format' do

      it %[should not barf if backtrace is nil] do
        exc = StandardError.new
        exc.backtrace.should be_nil
        lambda { exc.to_std_format }.should_not raise_error
      end
    end
  end
end

