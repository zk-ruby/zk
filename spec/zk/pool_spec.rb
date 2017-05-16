require 'spec_helper'

describe ZK::Pool do
  describe :Simple do
    include_context 'connection opts'

    before do
      report_realtime('opening pool') do
        @pool_size = 2
        @connection_pool = ZK::Pool::Simple.new(connection_host, @pool_size, :watcher => :default)
        @connection_pool.should be_open
      end
    end

    after do
      report_realtime("close_all!") do
        unless @connection_pool.closed?
          th = Thread.new do
            @connection_pool.close_all!
          end

          unless th.join(5) == th
            logger.warn { "Forcing pool closed!" }
            @connection_pool.force_close!
            th.join(5).should == th
          end
        end
      end

      report_realtime("closing") do
        ZK.open(connection_host) do |zk|
          begin
            zk.delete('/test_pool')
          rescue ZK::Exceptions::NoNode
          end
        end
      end
    end

    it "should allow you to execute commands on a connection" do
      @connection_pool.with_connection do |zk|
        zk.create("/test_pool", "", :mode => :ephemeral)
        zk.exists?("/test_pool").should be_true
      end
    end

    describe :method_missing do
      it %[should allow you to execute commands on the connection pool itself] do
        @connection_pool.create('/test_pool', '', :mode => :persistent)
        wait_until(2) { @connection_pool.exists?('/test_pool') }
        @connection_pool.exists?('/test_pool').should be_true
      end
    end

    describe :close_all! do
      it %[should shutdown gracefully] do
        latch = Latch.new

        @about_to_block = false

        @mutex = Mutex.new
        @cond = ConditionVariable.new
        @cnx = nil

        open_th = Thread.new do
          @mutex.synchronize do
            @cnx = @connection_pool.checkout(true)
            @cond.broadcast
          end
          latch.await(30) # don't time out
        end

        @mutex.synchronize do
          @cond.wait(@mutex) while @cnx.nil?
        end

        @cnx.should_not be_nil

        closing_th = Thread.new do
          @connection_pool.close_all!
        end

        wait_until(5) { @connection_pool.closing? }
        @connection_pool.should be_closing
        logger.debug { "connection pool is closing" }

        lambda { @connection_pool.with_connection { |c| c } }.should raise_error(ZK::Exceptions::PoolIsShuttingDownException)

        latch.release

        open_th.join(5).should == open_th

        @connection_pool.wait_until_closed

        @connection_pool.should be_closed

        lambda do
          closing_th.join(1).should == closing_th
          open_th.join(1).should == open_th
        end.should_not raise_error
      end
    end

    describe :force_close! do
      it %[should raise PoolIsShuttingDownException in a thread blocked waiting for a connection], :mri_187 => :broken do
        @cnx = []

        until @connection_pool.available_size <= 0
          @cnx << @connection_pool.checkout
        end

        @cnx.length.should_not be_zero

        # this exc nonsense is because 1.8.7's scheduler is broken
        @exc = nil

        th = Thread.new do
          begin
            @connection_pool.checkout(true)
          rescue
            @exc = $!
          end
        end

        # th.join_until { @connection_pool.count_waiters > 0 }
        # @connection_pool.count_waiters.should > 0

        @connection_pool.force_close!

        @connection_pool.wait_until_closed

        th.join(5).should == th
        @exc.should be_kind_of(ZK::Exceptions::PoolIsShuttingDownException)
      end
    end

    it "should allow watchers still" do
      @callback_called = false

      @path = '/_testWatch'

      @connection_pool.with_connection do |zk|
        begin
          zk.delete(@path)
        rescue ZK::Exceptions::NoNode
        end
      end

      @connection_pool.with_connection do |zk|
        zk.watcher.register(@path) do |event|

          @callback_called = true
          event.path.should == @path
        end

        zk.exists?(@path, :watch => true).should be_false
      end

      @connection_pool.with_connection do |zk|
        zk.create(@path, "", :mode => :ephemeral).should == @path
      end

      wait_until(1) { @callback_called }

      @callback_called.should be_true
    end

    # These tests are seriously yucky, but they show that when a client is !connected?
    # the pool behaves properly and will not return that client to the caller.

    describe 'health checking with disconnected client', :rbx => :broken do
      before do
        wait_until(2) { @connection_pool.available_size == 2 }
        @connection_pool.available_size.should == 2

        @connections = @connection_pool.connections
        @connections.length.should == 2

        @cnx1 = @connections.shift

        mock_sub = flexmock(:subscription)

        @mcnx1 = flexmock(@cnx1) do |m|
          m.should_receive(:connected?).at_least.once.and_return(false)
          m.should_receive(:on_connected).with(Proc).at_least.once.and_return(mock_sub)
        end

        @connections.unshift(@mcnx1)
      end

      after do
        @connections.delete(@mcnx1)
        @connections.unshift(@cnx1)
        [@cnx1, @cnx2].each { |c| @connection_pool.checkin(c) }
      end

      it %[should remove the disconnected client from the pool] do
        @connection_pool.available_size.should == 2

        @cnx2 = @connection_pool.checkout

        # this is gross and relies on knowing internal state
        @connection_pool.checkout(false).should be_false

        @cnx2.should_not be_nil
        @cnx2.should_not == @mcnx1

        @connection_pool.available_size.should == 0
        @connections.should include(@mcnx1)
      end
    end
  end # Simple

  describe :Bounded do
    include_context 'connection opts'

    before do
      @min_clients = 1
      @max_clients = 2
      @timeout = 10
      @connection_pool = ZK::Pool::Bounded.new(connection_host, :min_clients => @min_clients, :max_clients => @max_clients, :timeout => @timeout)
      @connection_pool.should be_open
      wait_until(2) { @connection_pool.available_size > 0 }
    end

    after do
      @connection_pool.force_close! unless @connection_pool.closed?
      @connection_pool.should be_closed
    end

    describe 'initial state' do
      it %[should have initialized the minimum number of clients] do
        @connection_pool.size.should == @min_clients
      end
    end

    describe 'should grow to max_clients' do
#       before do
#         require 'tracer'
#         Tracer.on
#       end

#       after do
#         Tracer.off
#       end

      it %[should grow if it can] do
        wait_until(2) { @connection_pool.available_size > 0 }
        @connection_pool.available_size.should > 0

        @connection_pool.size.should == 1

        logger.debug { "checking out @cnx1" }
        @cnx1 = @connection_pool.checkout
        @cnx1.should_not be_false

        @connection_pool.can_grow_pool?.should be_true

        logger.debug { "checking out @cnx2" }
        @cnx2 = @connection_pool.checkout
        @cnx2.should_not be_false
        @cnx2.should be_connected

        @cnx1.object_id.should_not == @cnx2.object_id

        [@cnx1, @cnx2].each { |c| @connection_pool.checkin(c) }
      end

      it %[should not grow past max_clients and block] do
        lose_q = Queue.new

        @cnx1 = @connection_pool.checkout
        @cnx1.should_not be_false

        @connection_pool.can_grow_pool?.should be_true

        @cnx2 = @connection_pool.checkout
        @cnx2.should_not be_false

        @connection_pool.can_grow_pool?.should be_false

        logger.debug { "spawning losing thread" }

        loser = Thread.new do
          @connection_pool.with_connection do |cnx|
            Thread.current[:cnx] = cnx
            logger.debug { "Losing thread got connection" }
            lose_q.pop
          end
          logger.debug { "losing thread exiting" }
        end

        # loser.join_until(5) { @connection_pool.count_waiters > 0 }
        # logger.debug { "count waiters: #{@connection_pool.count_waiters}" }
        # @connection_pool.count_waiters.should == 1

        loser[:cnx].should be_nil

        [@cnx1, @cnx2].each { |c| @connection_pool.checkin(c) }

        loser.join_until(2) { loser[:cnx] }
        loser[:cnx].should_not be_nil

        lose_q.enq(:release)

        lambda { loser.join(2).should == loser }.should_not raise_error

        logger.debug { "joined losing thread" }

        @connection_pool.count_waiters.should be_zero
        @connection_pool.available_size.should == 2
        @connection_pool.size.should == 2
      end
    end   # should grow to max_clients

  end
end
