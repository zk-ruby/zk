# quick tests for one of the support classes
require 'spec_helper'

describe EventCatcher do
  subject { EventCatcher.new }

  let!(:latch) { Latch.new }

  describe :wait_for do
    it %[should wake when an event is delivered] do

      th = Thread.new do
        subject.synchronize do
          logger.debug { "about to wait for created" }
          latch.release
          subject.wait_for_created
          logger.debug { "woke up, created must have been delivered" }
        end
        true
      end

      latch.await

      logger.debug { "th.status: #{th.status}" }

      subject.add(:created, 'blah')

      expect(th.join(2).value).to be(true)
    end
  end
end

