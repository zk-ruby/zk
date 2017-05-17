require 'spec_helper'

module ZK
  describe 'Extensions' do
    describe 'Exception#to_std_format' do

      it %[should not barf if backtrace is nil] do
        exc = StandardError.new
        expect(exc.backtrace).to be_nil
        expect { exc.to_std_format }.not_to raise_error
      end
    end
  end
end

