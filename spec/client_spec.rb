require File.join(File.dirname(__FILE__), %w[spec_helper])

describe ZK::Client do
  before do
    @zk = ZK.new("localhost:#{ZK_TEST_PORT}", :watcher => nil)
    wait_until{ @zk.connected? }
    @zk.rm_rf('/test')
  end

  after do
    @zk.rm_rf('/test')
    @zk.close!

    report_realtime("shutdown client") do
      wait_until(2) { @zk.closed? }
    end
  end

  describe :mkdir_p do
    before(:each) do
      @path_ary = %w[test mkdir_p path creation]
      @bogus_path = File.join('/', *@path_ary)
    end
    
    it %[should create all intermediate paths for the path givem] do
      @zk.should_not be_exists(@bogus_path)
      @zk.should_not be_exists(File.dirname(@bogus_path))
      @zk.mkdir_p(@bogus_path)
      @zk.should be_exists(@bogus_path)
    end
  end

  describe :stat do
    describe 'for a missing node' do
      before do
        @missing_path = '/thispathdoesnotexist'
        @zk.delete(@missing_path) rescue ZK::Exceptions::NoNode
      end

      it %[should not raise any error] do
        lambda { @zk.stat(@missing_path) }.should_not raise_error
      end

      it %[should return a Stat object] do
        @zk.stat(@missing_path).should be_kind_of(ZookeeperStat::Stat)
      end

      it %[should return a stat that not exists?] do
        @zk.stat(@missing_path).should_not be_exists
      end
    end
  end

  describe :block_until_node_deleted do
    before do
      @path = '/_bogualkjdhsna'
    end

    describe 'no node initially' do
      before do
        @zk.exists?(@path).should be_false
      end

      it %[should not block] do
        @a = false

        th = Thread.new do
          @zk.block_until_node_deleted(@path)
          @a = true
        end

        th.join(2)
        @a.should be_true
      end
    end

    describe 'node exists initially' do
      before do
        @zk.create(@path, '', :mode => :ephemeral)
        @zk.exists?(@path).should be_true
      end

      it %[should block until the node is deleted] do
        @a = false

        th = Thread.new do
          @zk.block_until_node_deleted(@path)
          @a = true
        end

        Thread.pass
        @a.should be_false

        @zk.delete(@path)

        wait_until(2) { @a }
        @a.should be_true
      end
    end
  end
end



