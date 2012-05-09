require 'spec_helper'

describe ZK::Client::Threaded do
  context do
    include_context 'threaded client connection'
    it_should_behave_like 'client'
  end

  describe :close! do
    describe 'from a threadpool thread' do
      include_context 'connection opts'

      before do
        @zk = ZK::Client::Threaded.new(*connection_args).tap { |z| wait_until { z.connected? } }
      end

      after do
        @zk.close! unless @zk.closed?
      end

      it %[should do the right thing and not fail] do
        # this is an extra special case where the user obviously hates us

        @zk.should be_kind_of(ZK::Client::Threaded) # yeah yeah, just be sure

        @zk.defer do
          @zk.close!
        end

        wait_until(5) { @zk.closed? }.should be_true 
      end
    end
  end

  unless defined?(::JRUBY_VERSION)
    describe :forked do
      include_context 'connection opts'

      before do
        @base_path = '/zktests'
        @pids_root = "#{@base_path}/pid"

        ZK.open(*connection_args) do |z| 
          z.rm_rf(@base_path)
          z.mkdir_p(@pids_root)
        end
      end

      after do
        if @pid
          begin
            Process.kill('TERM', @pid)
            pid, st = Process.wait2(@pid)
            logger.debug { "child #{@pid} exited with status: #{st.inspect}" }
          rescue Errno::ESRCH
          end
        end

        @zk.close! if @zk
        ZK.open(*connection_args) { |z| z.rm_rf(@base_path) }
      end

      it %[should deliver callbacks in the child] do
        pending_in_travis "skip this test, flaky in travis"
        
        logger.debug { "Process.pid of parent: #{Process.pid}" }

        @zk = ZK.new do |z|
          z.on_connected do
            logger.debug { "on_connected fired, writing pid to path #{@pids_root}/#{$$}" }
            z.create("#{@pids_root}/#{Process.pid}", Process.pid.to_s)
          end
        end

        @zk.create("#{@pids_root}/#{$$}", $$.to_s)

        event_catcher = EventCatcher.new

        @zk.register(@pids_root, :only => :child) do |event|
          event_catcher << event
        end

        @pid = fork do
          @zk.reopen
          @zk.wait_until_connected

          @zk.find(@base_path) { |n| puts "child: #{n.inspect}" }

          exit! 0
        end

        Process.waitall

        event_catcher.synchronize do
          unless event_catcher.child.empty?
            event_catcher.wait_for_child
            event_catcher.child.should_not be_empty
          end
        end

        @zk.should be_exists("#{@pids_root}/#{@pid}")

      end # should deliver callbacks in the child
    end # forked
  end # # jruby guard
end # ZK::Client::Threaded

