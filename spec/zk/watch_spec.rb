require 'spec_helper'

describe ZK do
  include_context 'connection opts'

  describe 'watchers' do
    before do
      mute_logger do
        @zk = ZK.new(*connection_args)

        @path = "/_testWatch"
        wait_until { @zk.connected? }
        @zk.rm_rf(@path)
      end
    end

    after do
      mute_logger do
        if @zk.connected?
          @zk.close! 
          wait_until { !@zk.connected? }
        end

        ZK.open(*connection_args) { |zk| zk.rm_rf(@path) }
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

    describe :regression do
      before do
        pending_in_travis("these tests take too long or time out")
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
    end

    it %[should restrict_new_watches_for? if a successul watch has been set] do
      @zk.stat(@path, :watch => true)
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

      lambda { @zk.get(@path, :watch => true) }.should raise_error(ZK::Exceptions::NoNode)

      @zk.event_handler.should_not be_restricting_new_watches_for(:data, @path)

      @zk.stat(@path, :watch => true)

      @zk.event_handler.should be_restricting_new_watches_for(:data, @path)

      @zk.create(@path, '')

      wait_while { events.empty? }

      events.should_not be_empty
    end

    it %[should call a child listener when the node is deleted] do
      events = []

      sub = @zk.register(@path) do |ev|
        logger.debug { "got event #{ev}" }
        events << ev
      end

      @zk.create(@path, '')

      # Watch for children
      @zk.children(@path, :watch => true)

      # Delete the node
      @zk.delete(@path)

      # We expect to see a delete event show up
      wait_while(5) { events.empty? }

      event = events.pop

      event.should_not be_nil

      event.path.should == @path
      event.type.should == Zookeeper::ZOO_DELETED_EVENT

      # Create the node again
      @zk.create(@path, '')

      # Watch for children again
      @zk.children(@path, :watch => true)

      # Delete the node again
      @zk.delete(@path)

      # We expect to see another delete event show up
      wait_while(5) { events.empty? }

      event = events.pop

      event.should_not be_nil

      event.path.should == @path
      event.type.should == Zookeeper::ZOO_DELETED_EVENT
    end

    describe ':all' do
      before do
        mute_logger do
          @other_path = "#{@path}2"
          @zk.rm_rf(@other_path)
        end
      end

      after do
        mute_logger do
          @zk.rm_rf(@other_path)
        end
      end

      it %[should receive all node events] do
        events = []

        sub = @zk.register(:all) do |ev|
          logger.debug { "got event #{ev}" }
          events << ev
        end

        @zk.stat(@path, :watch => true)
        @zk.stat(@other_path, :watch => true)

        @zk.create(@path)
        @zk.create(@other_path, 'blah')

        wait_until { events.length == 2 }.should be_true
      end
    end

    describe %[event interest] do
      context do # event catcher scope
        before do
          @events = EventCatcher.new

          [:created, :changed, :child, :deleted].each do |ev_name|

            @zk.register(@path, :only => ev_name) do |event|
              @events.add(ev_name, event)
            end

          end
        end

        it %[should deliver only the created event to the created block] do
          @events.synchronize do
            @zk.stat(@path, :watch => true).should_not exist

            @zk.create(@path)

            @events.wait_for_created

            @events.created.should_not be_empty
            @events.created.first.should be_node_created
            @events.all.should_not be_empty

            @zk.stat(@path, :watch => true).should exist

            @events.all.length.should == 1

            @zk.delete(@path)

            @events.wait_for_all
          end

          @events.all.length.should == 2

          # :deleted event was delivered, make sure it didn't get delivered to the :created block
          @events.created.length.should == 1
        end

        it %[should deliver only the changed event to the changed block] do
          @events.synchronize do
            @zk.create(@path)

            @zk.stat(@path, :watch => true).should exist

            @zk.set(@path, 'data')

            @events.wait_for_changed
          end

          @events.changed.should_not be_empty
          @events.changed.length.should == 1
          @events.changed.first.should be_node_changed

          @events.all.length.should == 1

          @events.synchronize do
            @zk.stat(@path, :watch => true).should exist
            @zk.delete(@path)
            @events.wait_for_all
          end

          @events.all.length.should == 2

          # :deleted event was delivered, make sure it didn't get delivered to the :changed block
          @events.changed.length.should == 1
        end

        it %[should deliver only the child event to the child block] do
          child_path = nil

          @events.synchronize do
            @zk.create(@path)
            @zk.children(@path, :watch => true).should be_empty

            child_path = @zk.create("#{@path}/m", '', :sequence => true)

            @events.wait_for_child

            @events.child.length.should == 1
            @events.child.first.should be_node_child

            @zk.stat(@path, :watch => true).should exist

            @events.all.length.should == 1

            @zk.set(@path, '') # equivalent to a 'touch'
            @events.wait_for_all
          end

          @events.all.length.should == 2

          # :changed event was delivered, make sure it didn't get delivered to the :child block
          @events.child.length.should == 1
        end

        it %[should deliver only the deleted event to the deleted block] do
          @events.synchronize do
            @zk.create(@path)
            @zk.stat(@path, :watch => true).should exist
            @zk.delete(@path)

            @events.wait_for_deleted
            @events.wait_while_all { |all| all.empty? }

            @events.deleted.should_not be_empty
            @events.deleted.first.should be_node_deleted
            @events.all.length.should == 1

            @zk.stat(@path, :watch => true).should_not exist

            @zk.create(@path)

            @events.wait_for_all
          end

          @events.all.length.should be > 1

          # :deleted event was delivered, make sure it didn't get delivered to the :created block
          @events.deleted.length.should == 1
        end
      end # event catcher scope

      it %[should deliver interested events to a block registered for multiple deliveries] do
        @events = []
        @events.extend(MonitorMixin)
        @cond = @events.new_cond

        @zk.register(@path, :only => [:created, :changed]) do |event|
          @events.synchronize do
            @events << event
            @cond.broadcast
          end
        end

        @events.synchronize do
          @zk.stat(@path, :watch => true).should_not exist

          @zk.create(@path)

          @cond.wait(5)

          @events.should_not be_empty
          @events.length.should == 1
          @events.first.should be_node_created

          @zk.stat(@path, :watch => true).should exist
          @zk.set(@path, 'blah')

          @cond.wait(5)
        end

        @events.length.should == 2
        @events.last.should be_node_changed
      end

      it %[should barf if an invalid event name is given] do
        lambda do
          @zk.register(@path, :only => :tripping) { }
        end.should raise_error(ArgumentError)
      end
    end # event interest
  end # watchers

  describe 'state watcher' do
    describe 'live-fire test' do
      before do
        @event = nil

        @zk = ZK.new(*connection_args) do |zk|
          @cnx_reg = zk.on_connected { |event| @event = event }
        end
      end

      after do
        @zk.close! if @zk and not @zk.closed?
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
          m.should_receive(:state).and_return(Zookeeper::Constants::ZOO_CONNECTED_STATE)
        end
      end
    end # registered listeners
  end
end

