require 'spec_helper'

describe ZK::NodeDeletionWatcher do
  include_context 'threaded client connection'

  before do
    @path = "#{@base_path}/node_deleteion_watcher_victim"

    @n = ZK::NodeDeletionWatcher.new(@zk, @path)
  end

  describe %[when the node already exists] do
    it %[blocks the caller until the node is deleted] do
      @zk.mkdir_p(@path)

      th = Thread.new { @n.block_until_deleted }
      
      @n.wait_until_blocked(5).should be_true

      logger.debug { "wait_until_blocked returned" }

      @n.should be_blocked

      @zk.rm_rf(@path)

      th.join(5).should == th
      @n.should_not be_blocked
      @n.should be_done
    end

    it %[should wake up if interrupt! is called] do
      @zk.mkdir_p(@path)

      @exc = nil

      th = Thread.new do
        begin
          @n.block_until_deleted
        rescue Exception => e
          @exc = e
        end
      end

      @n.wait_until_blocked(5)

      @n.should be_blocked

      @n.interrupt!
      th.join(5).should == th

      @exc.should be_kind_of(ZK::Exceptions::WakeUpException)
    end
  end

  describe %[when the node doesn't exist] do
    it %[should not block the caller and be done] do
      @zk.exists?(@path).should be_false

      th = Thread.new { @n.block_until_deleted }

      @n.wait_until_blocked
      @n.should_not be_blocked
      th.join(5).should == th
      @n.should be_done
    end
  end
end


