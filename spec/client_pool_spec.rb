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
        zk = ZK.new("localhost:#{ZK_TEST_PORT}")
        zk.delete('/test_pool') rescue ZK::Exceptions::NoNode
        zk.close!
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
end
