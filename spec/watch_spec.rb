require 'spec_helper'

describe ZK do
  describe do
    before do
      @cnx_str = "localhost:#{ZK_TEST_PORT}"
      @zk = ZK.new(@cnx_str)

      @path = "/_testWatch"
      wait_until { @zk.connected? }

      # make sure we start w/ clean state
      @zk.rm_rf(@path)
    end

    after do
      mute_logger do
        if @zk.connected?
          @zk.close! 
          wait_until { !@zk.connected? }
        end

        ZK.open(@cnx_str) { |zk| zk.rm_rf(@path) }
      end
    end

    it "should call back to path registers" do
      locker = Mutex.new
      callback_called = false

      @zk.register(@path) do |event|
        locker.synchronize do
          callback_called = true
        end
        event.path.should == @path
      end

      @zk.exists?(@path, :watch => true)
      @zk.create(@path, "", :mode => :ephemeral)

      wait_until(5) { locker.synchronize { callback_called } }
      callback_called.should be_true
    end

    # this is stupid, and a bad test, but we have to check that events 
    # don't get re-delivered to a single registered callback just because 
    # :watch => true was called twice
    #
    # again, we're testing a negative here, so consider this a regression check
    #
    def wait_for_events_to_not_be_delivered(events)
      lambda { wait_until(0.2) { events.length >= 2 } }.should raise_error(WaitWatchers::TimeoutError)
    end

    it %[should only deliver an event once to each watcher registered for exists?] do
      events = []

      sub = @zk.register(@path) do |ev|
        logger.debug "got event #{ev}"
        events << ev
      end

      2.times do
        @zk.exists?(@path, :watch => true).should_not be_true
      end

      @zk.create(@path, '', :mode => :ephemeral)

      wait_for_events_to_not_be_delivered(events)

      events.length.should == 1
    end

    it %[should only deliver an event once to each watcher registered for get] do
      events = []

      @zk.create(@path, 'one', :mode => :ephemeral)

      sub = @zk.register(@path) do |ev|
        logger.debug "got event #{ev}"
        events << ev
      end

      2.times do
        data, stat = @zk.get(@path, :watch => true)
        data.should == 'one'
      end

      @zk.set(@path, 'two')

      wait_for_events_to_not_be_delivered(events)

      events.length.should == 1
    end


    it %[should only deliver an event once to each watcher registered for children] do
      events = []

      @zk.create(@path, '')

      sub = @zk.register(@path) do |ev|
        logger.debug "got event #{ev}"
        events << ev
      end

      2.times do
        children = @zk.children(@path, :watch => true)
        children.should be_empty
      end

      @zk.create("#{@path}/pfx", '', :mode => :ephemeral_sequential)

      wait_for_events_to_not_be_delivered(events)

      events.length.should == 1
    end

    it %[should restrict_new_watches_for? if a successul watch has been set] do
      @zk.stat(@path, watch: true)
      @zk.event_handler.should be_restricting_new_watches_for(:data, @path)
    end

    it %[should not a block on new watches after an operation fails] do
      # this is a situation where we did get('/blah', :watch => true) but
      # got an exception, the next watch set should work

      events = []

      sub = @zk.register(@path) do |ev|
        logger.debug { "got event #{ev}" }
        events << ev
      end

      # get a path that doesn't exist with a watch

      lambda { @zk.get(@path, watch: true) }.should raise_error(ZK::Exceptions::NoNode)

      @zk.event_handler.should_not be_restricting_new_watches_for(:data, @path)

      @zk.stat(@path, watch: true)

      @zk.event_handler.should be_restricting_new_watches_for(:data, @path)

      @zk.create(@path, '')

      wait_while { events.empty? }

      events.should_not be_empty

    end
  end

  describe 'state watcher' do
    describe 'live-fire test' do
      before do
        @event = nil
        @cnx_str = "localhost:#{ZK_TEST_PORT}"

        @zk = ZK.new(@cnx_str) do |zk|
          @cnx_reg = zk.on_connected { |event| @event = event }
        end
      end

      it %[should fire the registered callback] do
        wait_while { @event.nil? }
        @event.should_not be_nil
      end
    end

    describe 'registered listeners' do
      before do
        @event = flexmock(:event) do |m|
          m.should_receive(:type).and_return(-1)
          m.should_receive(:zk=).with(any())
          m.should_receive(:node_event?).and_return(false)
          m.should_receive(:state_event?).and_return(true)
          m.should_receive(:state).and_return(ZookeeperConstants::ZOO_CONNECTED_STATE)
        end
      end
    end
  end
end

