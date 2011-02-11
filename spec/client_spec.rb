require File.join(File.dirname(__FILE__), %w[spec_helper])

describe ZK::Client do
  describe :mkdir_p do
    before(:each) do
      @zk = ZK.new("localhost:#{ZK_TEST_PORT}", :watcher => nil)
      wait_until{ @zk.connected? }
      @zk.rm_rf('/test')

      @path_ary = %w[test mkdir_p path creation]
      @bogus_path = File.join('/', *@path_ary)
    end
    
    after(:each) do
      @zk.rm_rf('/test')
      @zk.close!
      wait_until{ @zk.closed? }
    end

    it %[should create all intermediate paths for the path givem] do
      @zk.should_not be_exists(@bogus_path)
      @zk.should_not be_exists(File.dirname(@bogus_path))
      @zk.mkdir_p(@bogus_path)
      @zk.should be_exists(@bogus_path)
    end
  end
end


