require 'spec_helper'

describe ZK::NodeDeletionWatcher do
  include_context 'threaded client connection'

  before do
    @path = "#{@base_path}/node_deleteion_watcher_victim"

    @ndw = ZK::NodeDeletionWatcher.new(@zk, @path)
  end

  describe %[when the node already exists] do
    it %[blocks the caller until the node is deleted] do
      @zk.mkdir_p(@path)

      th = Thread.new { @ndw.block_until_deleted }
      
      @ndw.wait_until_blocked(5).should be_true

      logger.debug { "wait_until_blocked returned" }

      @ndw.should be_blocked

      @zk.rm_rf(@path)

      th.join(5).should == th
      @ndw.should_not be_blocked
    end
  end
end


