require 'spec_helper'

describe ZK::Client do
  before do
    @connection_string = "localhost:#{ZK_TEST_PORT}"
    @zk = ZK.new(@connection_string)
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

      shared_examples_for 'session death' do
        def deliver_session_event_to(event_num, zk)
          # jeez, Zookeeper callbacks are so frustratingly stupid
          bogus_event = ZookeeperCallbacks::WatcherCallback.new
          bogus_event.initialize_context(:type => -1, :state => event_num, :path => '', :context => 'bogustestevent')
          # XXX: this is bad because we're in the wrong thread, but we'll fix this after the next Zookeeper release
          zk.event_handler.process(bogus_event)
        end

        before do
          @other_zk = ZK.new(@connection_string)
        end

        after do
          @other_zk.close! unless @other_zk.closed?
        end

        it %[should wake up in the case of an expired session and throw an exception] do
          @a = false

          @other_zk.event_handler.register_state_handler(zoo_state) do |event|
            @a = event
          end

          th = Thread.new do
            @other_zk.block_until_node_deleted(@path)
          end

          wait_until(2) { th.status == 'sleep' }

          # not on the other thread, this may be bad
          deliver_session_event_to(zoo_state, @other_zk)

          # ditto, this is probably happening synchrnously
          wait_until(2) { @a }

          lambda { th.join(0.1) }.should raise_error(zoo_error_class)
        end
      end

      describe 'exceptional conditions' do
        describe 'ZOO_EXPIRED_SESSION_STATE' do
          let(:zoo_state) { ZookeeperConstants::ZOO_EXPIRED_SESSION_STATE }
          let(:zoo_error_class) { ZookeeperExceptions::ZookeeperException::SessionExpired }

          it_behaves_like 'session death'
        end

        describe 'ZOO_CONNECTING_STATE' do
          let(:zoo_state) { ZookeeperConstants::ZOO_CONNECTING_STATE }
          let(:zoo_error_class) { ZookeeperExceptions::ZookeeperException::NotConnected }

          it_behaves_like 'session death'
        end

        describe 'ZOO_CLOSED_STATE' do
          let(:zoo_state) { ZookeeperConstants::ZOO_CLOSED_STATE }
          let(:zoo_error_class) { ZookeeperExceptions::ZookeeperException::ConnectionClosed }

          it_behaves_like 'session death'
        end
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

      def ensure_event_delivery!
        @sub ||= @zk.event_handler.register(@path) do |event|
          logger.debug { "got event: #{event.inspect}" } 
          @queue << event
        end

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



