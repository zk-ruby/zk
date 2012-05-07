# quick tests for one of the support classes
require 'spec_helper'

describe EventCatcher do
  subject { EventCatcher.new }

  describe :wait_for do
    it %[should wake when an event is delivered] do
      pending "this has a pretty awful race in it"

      th = Thread.new do
        subject.synchronize do
          logger.debug { "about to wait for created" }
          subject.wait_for_created
          logger.debug { "woke up, created must have been delivered" }
        end
        true
      end

      th.run
      Thread.pass until th.status == 'sleep'

      logger.debug { "th.status: #{th.status}" }

      subject.add(:created, 'blah')

      th.join(2).value.should be_true
    end
  end
end

