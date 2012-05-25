require 'spec_helper'

describe ZK::Locker do
  include_context 'threaded client connection'

  describe :cleanup do
    it %[should remove dead lock directories] do
      locker = @zk.locker('legit')
      locker.lock
      locker.assert!

      bogus_lock_dir_names = %w[a b c d e f g]
      bogus_lock_dir_names.each { |n| @zk.create("#{ZK::Locker.default_root_lock_node}/#{n}") }

      ZK::Locker.cleanup(@zk)

      lambda { locker.assert! }.should_not raise_error

      bogus_lock_dir_names.each { |n| @zk.stat("#{ZK::Locker.default_root_lock_node}/#{n}").should_not exist }

    end
  end
end
