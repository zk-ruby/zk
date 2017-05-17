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
        expect(event.path).to eq(@path)
      end

      @zk.exists?(@path, :watch => true)
      @zk.create(@path, "", :mode => :ephemeral)

      wait_until(5) { locker.synchronize { callback_called } }
      expect(callback_called).to be(true)
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
        expect { wait_until(0.2) { events.length >= 2 } }.to raise_error(WaitWatchers::TimeoutError)
      end

      it %[should only deliver an event once to each watcher registered for exists?] do
        events = []

        sub = @zk.register(@path) do |ev|
          logger.debug "got event #{ev}"
          events << ev
        end

        2.times do
          expect(@zk.exists?(@path, :watch => true)).not_to be(true)
        end

        @zk.create(@path, '', :mode => :ephemeral)

        wait_for_events_to_not_be_delivered(events)

        expect(events.length).to eq(1)
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
          expect(data).to eq('one')
        end

        @zk.set(@path, 'two')

        wait_for_events_to_not_be_delivered(events)

        expect(events.length).to eq(1)
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
          expect(children).to be_empty
        end

        @zk.create("#{@path}/pfx", '', :mode => :ephemeral_sequential)

        wait_for_events_to_not_be_delivered(events)

        expect(events.length).to eq(1)
      end
    end

    it %[should restrict_new_watches_for? if a successul watch has been set] do
      @zk.stat(@path, :watch => true)
      expect(@zk.event_handler).to be_restricting_new_watches_for(:data, @path)
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

      expect { @zk.get(@path, :watch => true) }.to raise_error(ZK::Exceptions::NoNode)

      expect(@zk.event_handler).not_to be_restricting_new_watches_for(:data, @path)

      @zk.stat(@path, :watch => true)

      expect(@zk.event_handler).to be_restricting_new_watches_for(:data, @path)

      @zk.create(@path, '')

      wait_while { events.empty? }

      expect(events).not_to be_empty
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

      expect(event).not_to be_nil

      expect(event.path).to eq(@path)
      expect(event.type).to eq(Zookeeper::ZOO_DELETED_EVENT)

      # Create the node again
      @zk.create(@path, '')

      # Watch for children again
      @zk.children(@path, :watch => true)

      # Delete the node again
      @zk.delete(@path)

      # We expect to see another delete event show up
      wait_while(5) { events.empty? }

      event = events.pop

      expect(event).not_to be_nil

      expect(event.path).to eq(@path)
      expect(event.type).to eq(Zookeeper::ZOO_DELETED_EVENT)
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

        expect(wait_until { events.length == 2 }).to be(true)
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
            expect(@zk.stat(@path, :watch => true)).not_to exist

            @zk.create(@path)

            @events.wait_for_created

            expect(@events.created).not_to be_empty
            expect(@events.created.first).to be_node_created
            expect(@events.all).not_to be_empty

            expect(@zk.stat(@path, :watch => true)).to exist

            expect(@events.all.length).to eq(1)

            @zk.delete(@path)

            @events.wait_for_all
          end

          expect(@events.all.length).to eq(2)

          # :deleted event was delivered, make sure it didn't get delivered to the :created block
          expect(@events.created.length).to eq(1)
        end

        it %[should deliver only the changed event to the changed block] do
          @events.synchronize do
            @zk.create(@path)

            expect(@zk.stat(@path, :watch => true)).to exist

            @zk.set(@path, 'data')

            @events.wait_for_changed
          end

          expect(@events.changed).not_to be_empty
          expect(@events.changed.length).to eq(1)
          expect(@events.changed.first).to be_node_changed

          expect(@events.all.length).to eq(1)

          @events.synchronize do
            expect(@zk.stat(@path, :watch => true)).to exist
            @zk.delete(@path)
            @events.wait_for_all
          end

          expect(@events.all.length).to eq(2)

          # :deleted event was delivered, make sure it didn't get delivered to the :changed block
          expect(@events.changed.length).to eq(1)
        end

        it %[should deliver only the child event to the child block] do
          child_path = nil

          @events.synchronize do
            @zk.create(@path)
            expect(@zk.children(@path, :watch => true)).to be_empty

            child_path = @zk.create("#{@path}/m", '', :sequence => true)

            @events.wait_for_child

            expect(@events.child.length).to eq(1)
            expect(@events.child.first).to be_node_child

            expect(@zk.stat(@path, :watch => true)).to exist

            expect(@events.all.length).to eq(1)

            @zk.set(@path, '') # equivalent to a 'touch'
            @events.wait_for_all
          end

          expect(@events.all.length).to eq(2)

          # :changed event was delivered, make sure it didn't get delivered to the :child block
          expect(@events.child.length).to eq(1)
        end

        it %[should deliver only the deleted event to the deleted block] do
          @events.synchronize do
            @zk.create(@path)
            expect(@zk.stat(@path, :watch => true)).to exist
            @zk.delete(@path)

            @events.wait_for_deleted
            @events.wait_while_all { |all| all.empty? }

            expect(@events.deleted).not_to be_empty
            expect(@events.deleted.first).to be_node_deleted
            expect(@events.all.length).to eq(1)

            expect(@zk.stat(@path, :watch => true)).not_to exist

            @zk.create(@path)

            @events.wait_for_all
          end

          expect(@events.all.length).to be > 1

          # :deleted event was delivered, make sure it didn't get delivered to the :created block
          expect(@events.deleted.length).to eq(1)
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
          expect(@zk.stat(@path, :watch => true)).not_to exist

          @zk.create(@path)

          @cond.wait(5)

          expect(@events).not_to be_empty
          expect(@events.length).to eq(1)
          expect(@events.first).to be_node_created

          expect(@zk.stat(@path, :watch => true)).to exist
          @zk.set(@path, 'blah')

          @cond.wait(5)
        end

        expect(@events.length).to eq(2)
        expect(@events.last).to be_node_changed
      end

      it %[should barf if an invalid event name is given] do
        expect do
          @zk.register(@path, :only => :tripping) { }
        end.to raise_error(ArgumentError)
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
        expect(@event).not_to be_nil
      end
    end
  end
end

