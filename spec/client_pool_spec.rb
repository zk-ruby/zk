require File.join(File.dirname(__FILE__), %w[spec_helper])

require 'tracer'

describe ZK::Pool do
  describe :Simple do

    before do
      report_realtime('opening pool') do
        @pool_size = 2
        @connection_pool = ZK::Pool::Simple.new("localhost:#{ZK_TEST_PORT}", @pool_size, :watcher => :default)
        @connection_pool.should be_open
      end
    end

    after do
      report_realtime("close_all!") do
        @connection_pool.close_all! unless @connection_pool.closed?
      end

      report_realtime("closing") do
        ZK.open("localhost:#{ZK_TEST_PORT}") do |zk|
          zk.delete('/test_pool') rescue ZK::Exceptions::NoNode
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
        release_q  = Queue.new

        @about_to_block = false

        open_th = Thread.new do
          @connection_pool.with_connection do |cnx|
            @about_to_block = true
            # wait for signal to release our connection
            release_q.pop
          end
        end

        wait_until(2) { @about_to_block }
        @about_to_block.should be_true

        release_q.num_waiting.should == 1

        closing_th = Thread.new do
          @connection_pool.close_all!
        end

        wait_until(2) { @connection_pool.closing? }
        @connection_pool.should be_closing

        lambda { @connection_pool.with_connection { |c| } }.should raise_error(ZK::Exceptions::PoolIsShuttingDownException)

        release_q << :ok_let_go

        wait_until(2) { @connection_pool.closed? }
        @connection_pool.should be_closed

        lambda do
          closing_th.join(1).should == closing_th
          open_th.join(1).should == open_th
        end.should_not raise_error
      end
    end

    it "should allow watchers still" do
#       pending "No idea why this is busted"

      @callback_called = false

      @path = '/_testWatch'

      @connection_pool.with_connection do |zk|
        zk.delete(@path) rescue ZK::Exceptions::NoNode
      end

      @connection_pool.with_connection do |zk|
        $stderr.puts "registering callback"
        zk.watcher.register(@path) do |event|
          $stderr.puts "callback fired! event: #{event.inspect}"

          @callback_called = true
          event.path.should == @path
          $stderr.puts "signaling other waiters"
        end

        $stderr.puts "setting up watcher"
        zk.exists?(@path, :watch => true).should be_false
      end

      @connection_pool.with_connection do |zk|
        $stderr.puts "creating path"
        zk.create(@path, "", :mode => :ephemeral).should == @path
      end

      wait_until(1) { @callback_called }

      @callback_called.should be_true
    end
  end # Client

  describe :Bounded do
    before do
      @min_clients = 1
      @max_clients = 2
      @connection_pool = ZK::Pool::Bounded.new("localhost:#{ZK_TEST_PORT}", :min_clients => @min_clients, :max_clients => @max_clients, :timeout => @timeout)
      @connection_pool.should be_open
    end

    after do
      @connection_pool.close_all! unless @connection_pool.closed?
    end

    describe 'initial state' do
      it %[should have initialized the minimum number of clients] do
        @connection_pool.size.should == @min_clients
      end
    end

    describe 'should grow to max_clients' do
      before do
#         require 'tracer'
#         Tracer.on
      end

      after do
#         Tracer.off
      end

      it %[should grow if it can] do
        q1 = Queue.new

        @connection_pool.size.should == 1

        th1 = Thread.new do
          @connection_pool.with_connection do |cnx|
            Thread.current[:cnx] = cnx
            q1.pop  # block here
          end
        end

        th1.run

        wait_until(2) { th1[:cnx] }

        th2 = Thread.new do
          @connection_pool.with_connection do |cnx|
            Thread.current[:cnx] = cnx
            q1.pop
          end
        end

        th2.run

        wait_until(2) { th2[:cnx] }
        th2[:cnx].should_not be_nil
        th2[:cnx].should be_connected

        @connection_pool.size.should == 2
        @connection_pool.available_size.should be_zero

        2.times { q1.enq(:release_cnx) }

        lambda do
          th1.join(1).should == th1
          th2.join(1).should == th2
        end.should_not raise_error

        @connection_pool.size.should == 2
        @connection_pool.available_size.should == 2
      end

      it %[should not grow past max_clients and block] do
        win_q = Queue.new
        lose_q = Queue.new

        threads = []

        2.times do
          threads << Thread.new do
            @connection_pool.with_connection do |cnx|
              Thread.current[:cnx] = cnx
              win_q.pop
            end
          end
        end

        wait_until(2) { threads.all? { |th| th[:cnx] } }
        threads.each { |th| th[:cnx].should_not be_nil }

        loser = Thread.new do
          @connection_pool.with_connection do |cnx|
            Thread.current[:cnx] = cnx
            lose_q.pop
          end
        end

        wait_until(2) { @connection_pool.count_waiters > 0 }
        @connection_pool.count_waiters.should == 1

        loser[:cnx].should be_nil

        2.times { win_q.enq(:release) }

        lambda { threads.each { |th| th.join(2).should == th } }.should_not raise_error

        wait_until(2) { loser[:cnx] }

        loser[:cnx].should_not be_nil

        lose_q.enq(:release)

        lambda { loser.join(2).should == loser }.should_not raise_error
      end
    end
  end
end
