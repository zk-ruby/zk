shared_examples_for 'client' do
  describe :mkdir_p do
    before do
      base = @base_path.sub(%r_^/_, '')

      @path_ary = %W[#{base} test mkdir_p path creation]
      @bogus_path = File.join('', *@path_ary)
    end

    it %[should create all intermediate paths for the path givem] do
      expect(@zk.exists?(@bogus_path)).to be(false)
      expect(@zk.exists?(File.dirname(@bogus_path))).to be(false)
      @zk.mkdir_p(@bogus_path)
      expect(@zk.exists?(@bogus_path)).to be(true)
    end

    it %[should place the data only at the leaf node] do
      @zk.mkdir_p(@bogus_path, :data => 'foobar')
      expect(@zk.get(@bogus_path).first).to eq('foobar')

      path = ''
      @path_ary[0..-2].each do |el|
        path = File.join(path, el)
        expect(@zk.get(path).first).to eq('')
      end
    end

    it %[should replace the data at the leaf node if it already exists] do
      @zk.mkdir_p(@bogus_path, :data => 'blahfoo')
      @zk.mkdir_p(@bogus_path, :data => 'foodink')
      expect(@zk.get(@bogus_path).first).to eq('foodink')
    end
  end

  # nail down all possible cases
  describe :create do
    describe 'only path given' do
      it %[should create a node with blank data] do
        @zk.create(@base_path)
        expect(@zk.get(@base_path).first).to eq('')
      end
    end

    describe 'path and data given' do
      it %[should create a node with the path and data] do
        @zk.create(@base_path, 'blah')
        expect(@zk.get(@base_path).first).to eq('blah')
      end
    end

    describe 'path and sequential' do
      it %[should create a sequential node with blank data] do
        @zk.create(@base_path)
        path = @zk.create("#{@base_path}/v", :sequential => true)
        expect(path.start_with?(@base_path)).to be(true)

        expect(File.basename(path)).to match(/v\d+/)

        expect(@zk.get(path).first).to eq('')
      end

      it %[should create a sequential node with given data] do
        @zk.create(@base_path)
        path = @zk.create("#{@base_path}/v", 'thedata', :sequential => true)
        expect(path.start_with?(@base_path)).to be(true)

        expect(File.basename(path)).to match(/v\d+/)

        data, st = @zk.get(path)
        expect(data).to eq('thedata')
        expect(st).not_to be_ephemeral
      end
    end

    describe 'path and ephemeral' do
      it %[should create an ephemeral node with blank data] do
        @zk.create(@base_path, :ephemeral => true)
        expect(@zk.get(@base_path).last).to be_ephemeral
      end

      it %[should create an ephemeral node with given data] do
        @zk.create(@base_path, 'thedata', :ephemeral => true)
        data, stat = @zk.get(@base_path)
        expect(data).to eq('thedata')
        expect(stat).to be_ephemeral
      end
    end

    describe 'path and sequential and ephemeral' do
      it %[should create a sequential ephemeral node with blank data] do
        @zk.create(@base_path)
        path = @zk.create("#{@base_path}/v", :sequential => true, :ephemeral => true)
        expect(path.start_with?(@base_path)).to be(true)

        expect(File.basename(path)).to match(/v\d+/)

        data, st = @zk.get(path)
        expect(data).to eq('')
        expect(st).to be_ephemeral
      end

      it %[should create a sequential ephemeral node with given data] do
        @zk.create(@base_path)
        path = @zk.create("#{@base_path}/v", 'thedata', :sequential => true, :ephemeral => true)
        expect(path.start_with?(@base_path)).to be(true)

        expect(File.basename(path)).to match(/v\d+/)

        data, st = @zk.get(path)
        expect(data).to eq('thedata')
        expect(st).to be_ephemeral
      end
    end

    it %[should barf if someone hands 3 params] do
      expect { @zk.create(@base_path, 'data', :sequence) }.to raise_error(ArgumentError)
    end

    it %[should barf if both :sequence and :sequential are given] do
      expect { @zk.create(@base_path, 'data', :sequence => true, :sequential => true) }.to raise_error(ArgumentError)
    end

    describe %[:ignore option] do
      it %[should squelch node_exists] do
        @zk.create(@base_path)

        expect { expect(@zk.create(@base_path, :ignore => :node_exists)).to be_nil }.not_to raise_error
      end

      it %[should squelch no_node] do
        expect { expect(@zk.create("#{@base_path}/foo/bar/baz", :ignore => :no_node)).to be_nil }.not_to raise_error
      end
    end

    describe %[:or option] do
      let(:path) { "#{@base_path}/foo/bar" }

      it %[should barf if anything but the the :set value is given] do
        expect { @zk.create(path, :or => :GFY) }.to raise_error(ArgumentError)
      end

      def create_args(opts={})
        proc do
          begin
            @zk.create(path, opts.merge(:or => :set))
          ensure
            @zk.rm_rf(path)
          end
        end
      end

      it %[should barf if any node option besides 'persistent' is given] do
        expect(create_args(:persistent => true)).not_to         raise_error
        expect(create_args(:sequential => true)).to             raise_error(ArgumentError)
        expect(create_args(:mode => :ephemeral)).to             raise_error(ArgumentError)
        expect(create_args(:mode => :ephemeral_sequential)).to  raise_error(ArgumentError)
        expect(create_args(:mode => :sequential)).to            raise_error(ArgumentError)
      end

      it %[should replace the data at the leaf node if it already exists] do
        @zk.mkdir_p(path, :data => 'foodink')
        @zk.create(path, 'blahfoo', :or => :set)
        expect(@zk.get(path).first).to eq('blahfoo')
      end

      it %[should create the intermediate paths] do
        expect { @zk.create(path, 'foobar', :or => :set) }.not_to raise_error

        expect(@zk.stat(@base_path)).to exist
        expect(@zk.stat("#{@base_path}/foo")).to exist
      end
    end
  end

  describe :delete do
    describe %[:ignore option] do
      it %[should squelch not_empty] do
        @zk.create(@base_path)
        @zk.create("#{@base_path}/blah")

        expect { expect(@zk.delete(@base_path, :ignore => :not_empty)).to be_nil }.not_to raise_error
      end

      it %[should squelch no_node] do
        expect { expect(@zk.delete("#{@base_path}/foo/bar/baz", :ignore => :no_node)).to be_nil }.not_to raise_error
      end

      it %[should squelch bad_version] do
        @zk.create(@base_path)
        expect { expect(@zk.delete("#{@base_path}", :version => 7, :ignore => :bad_version)).to be_nil }.not_to raise_error
      end
    end
  end

  describe :stat do
    describe 'for a missing node' do
      before do
        @missing_path = '/thispathdoesnotexist'
        begin
          @zk.delete(@missing_path)
        rescue ZK::Exceptions::NoNode
        end
      end

      it %[should not raise any error] do
        expect { @zk.stat(@missing_path) }.not_to raise_error
      end

      it %[should return a Stat object] do
        expect(@zk.stat(@missing_path)).to be_kind_of(Zookeeper::Stat)
      end

      it %[should return a stat that not exists?] do
        expect(@zk.stat(@missing_path)).not_to be_exists
      end
    end
  end

  describe :set do
    describe %[:ignore option] do
      it %[should squelch no_node] do
        expect { expect(@zk.set("#{@base_path}/foo/bar/baz", '', :ignore => :no_node)).to be_nil }.not_to raise_error
      end

      it %[should squelch bad_version] do
        @zk.create(@base_path)
        expect { expect(@zk.set("#{@base_path}", '', :version => 7, :ignore => :bad_version)).to be_nil }.not_to raise_error
      end
    end
  end

  describe :block_until_node_deleted do
    before do
      @path = '/_bogualkjdhsna'
    end

    describe 'no node initially' do
      before do
        expect(@zk.exists?(@path)).to be(false)
      end

      it %[should not block] do
        @a = false

        th = Thread.new do
          @zk.block_until_node_deleted(@path)
          @a = true
        end

        th.join(2)
        expect(@a).to be(true)
      end
    end

    describe 'node exists initially' do
      before do
        @zk.create(@path, :mode => :ephemeral)
        expect(@zk.exists?(@path)).to be(true)
      end

      it %[should block until the node is deleted] do
        @a = false

        Thread.new do
          @zk.block_until_node_deleted(@path)
          @a = true
        end

        Thread.pass
        expect(@a).to be(false)

        @zk.delete(@path)

        wait_until(2) { @a }
        expect(@a).to be(true)
      end
    end
  end

  describe 'session_id and session_passwd' do
    it %[should expose the underlying session_id] do
      expect(@zk.session_id).to be_kind_of(Integer)
    end

    it %[should expose the underlying session_passwd] do
      expect(@zk.session_passwd).to be_kind_of(String)
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

        expect(@zk.exists?(@path, :watch => true)).to be(false)
        @zk.create(@path)

        logger.debug { "waiting for event delivery" }

        wait_until(2) do
          begin
            event = @queue.pop(true)
            logger.debug { "got event: #{event}" }
            @events << event
            true
          rescue ThreadError
            false
          end
        end

        # first watch delivered correctly
        expect(@events.length).to be > 0
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

        logger.debug { "events: #{@events.inspect}" }
      end
    end

  end # reopen

  describe 'reconnection' do
    it %[should if it receives a client_invalid? event] do
      # note: we can't trust the events to be delivered in any particular order
      # since they're happening on two different threads. if we see we're connected
      # in the beginning, that there was a disconnection, then a reopen, that's
      # probably fine.
      #
      # we also check that the session_id was changed, which is the desired effect

      orig_session_id = @zk.session_id
      expect(@zk).to be_connected

      props = {
        :session_event?   => true,
        :node_event?      => false,
        :client_invalid?  => true,
        :state_name       => 'ZOO_EXPIRED_SESSION_STATE',
        :state            => Zookeeper::ZOO_EXPIRED_SESSION_STATE,
      }

      bogus_event = instance_double(Zookeeper::Callbacks::WatcherCallback, props)
      expect(bogus_event).to receive(:zk=).with(@zk).once

      mutex = Monitor.new
      cond  = mutex.new_cond
      events = []

      @sub = @zk.on_state_change do |event|
        mutex.synchronize do
          logger.debug { "event: #{event.inspect}" }
          events << event.state
          cond.broadcast
        end
      end

      mutex.synchronize do
        expect(events).to be_empty
        @zk.event_handler.process(bogus_event)
      end

      logger.debug { "events: #{events.inspect}" }

      mutex.synchronize do
        time_to_stop = Time.now + 2
        cond.wait_while { (events.length < 2 ) && (Time.now < time_to_stop) }
      end

      expect(events).to include(Zookeeper::ZOO_EXPIRED_SESSION_STATE)
      expect(events).to include(Zookeeper::ZOO_CONNECTED_STATE)
      expect(@zk.session_id).not_to eq(orig_session_id)
    end
  end # reconnection

  describe :on_exception do
    it %[should register a callback that will be called if an exception is raised on the threadpool] do
      @ary = []

      @zk.on_exception { |exc| @ary << exc }

      @zk.defer { raise "ZOMG!" }

      wait_while(2) { @ary.empty? }

      expect(@ary.length).to eq(1)

      e = @ary.shift

      expect(e).to be_kind_of(RuntimeError)
      expect(e.message).to eq('ZOMG!')
    end
  end

  describe :on_threadpool? do
    it %[should be true if we're on the threadpool] do
      @ary = []

      @zk.defer { @ary << @zk.on_threadpool? }

      wait_while(2) { @ary.empty? }
      expect(@ary.length).to eq(1)
      expect(@ary.first).to be(true)
    end
  end
end

