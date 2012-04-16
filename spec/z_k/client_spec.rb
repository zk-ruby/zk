require 'spec_helper'

describe ZK::Client do
  before do
    @zk = ZK.new("localhost:#{ZK_TEST_PORT}")
    wait_until{ @zk.connected? }
    @zk.rm_rf('/test')
  end

  after do
    @zk.rm_rf('/test')
    @zk.close!

    wait_until(2) { @zk.closed? }
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

  describe 'session_id and session_passwd' do
    it %[should expose the underlying session_id] do
      @zk.session_id.should be_kind_of(Fixnum)
    end

    it %[should expose the underlying session_passwd] do
      @zk.session_passwd.should be_kind_of(String)
    end
  end

  describe 'reopen' do
    describe 'watchers' do
      before do
        @path = '/testwatchers'
        @queue = Queue.new
      end

      after do
        @zk.delete(@path)
      end

      def register_watch!
        @sub = @zk.event_handler.register(@path) do |event|
          logger.debug { "got event: #{event.inspect}" } 
          @queue << event
        end
      end

      def ensure_event_delivery!
        register_watch!

        @zk.exists?(@path, :watch => true).should be_false
        @zk.create(@path, '')

        logger.debug { "waiting for event delivery" } 

        wait_until(2) do 
          begin
            @events << @queue.pop(true)
            true
          rescue ThreadError
            false
          end
        end

        # first watch delivered correctly
        @events.length.should > 0
      end

      it %[should fire re-registered watchers after reopen (#9)] do
        @events = []

        logger.debug { "ensure event delivery" }
        ensure_event_delivery!

        logger.debug { "reopening connection" }
        @zk.reopen

        wait_until(2) { @zk.connected? }

        logger.debug { "deleting path" }
        @zk.delete(@path)

        logger.debug { "clearing events" }
        @events.clear

        logger.debug  { "taunt them a second time" }
        ensure_event_delivery!
      end
    end
  end
end



