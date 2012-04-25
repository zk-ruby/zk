shared_examples_for 'client' do
  describe :mkdir_p do
    before(:each) do
      @path_ary = %w[test mkdir_p path creation]
      @bogus_path = File.join('/', *@path_ary)
      @zk.rm_rf('/test')
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
        @zk.delete(@path) rescue ZK::Exceptions::NoNode
      end

#       after do
#         logger.info { "AFTER EACH" } 
#         @zk.delete(@path)
#       end

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

  end # reopen

  describe 'reconnection' do
    it %[should if it receives a client_invalid? event] do
      flexmock(@zk) do |m|
        m.should_receive(:reopen).with(0).once
      end

      bogus_event = flexmock(:expired_session_event, :session_event? => true, :client_invalid? => true, :state_name => 'ZOO_EXPIRED_SESSION_STATE')

      @zk.raw_event_handler(bogus_event)
    end
  end # reconnection

  describe :on_exception do
    it %[should register a callback that will be called if an exception is raised on the threadpool] do
      @ary = []

      @zk.on_exception { |exc| @ary << exc }
        
      @zk.defer { raise "ZOMG!" }

      wait_while(2) { @ary.empty? }

      @ary.length.should == 1

      e = @ary.shift

      e.should be_kind_of(RuntimeError)
      e.message.should == 'ZOMG!'
    end
  end

  describe :on_threadpool? do
    it %[should be true if we're on the threadpool] do
      @ary = []

      @zk.defer { @ary << @zk.on_threadpool? }

      wait_while(2) { @ary.empty? }
      @ary.length.should == 1
      @ary.first.should be_true
    end
  end
end

