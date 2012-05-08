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

  describe :forked do
    include_context 'connection opts'

    before do
      ZK.open(*connection_args) { |z| z.rm_rf(@base_path) }
      @pids_root = "#{@base_path}/pid"
    end

    after do
      if @pid
        Process.kill('TERM', @pid)
        pid, st = Process.wait2(@pid)
        logger.debug { "child #{@pid} exited with status: #{st.inspect}" }
      end

      @zk.close! if @zk
      ZK.open(*connection_args) { |z| z.rm_rf(@base_path) }
    end

    it %[should deliver callbacks in the child] do
      @zk = ZK.new do |z|
        z.on_connected do
          @zk.create("#{@pids_root}/#{$$}", $$.to_s)
        end
      end

      @zk.mkdir_p(@pids_root)

      @zk.create("#{@pids_root}/#{$$}", $$.to_s)

      event_catcher = EventCatcher.new

      @zk.register(@pids_root, :only => :child) do |event|
        event_catcher << event
      end

      th = Thread.new do
        event_catcher.wait_for_child
        event_catcher.child
      end

      @pid = fork do
        @zk.reopen
        sleep(0.01) until @zk.connected?

        @zk.find(@base_path) { |n| puts "child: #{n.inspect}" }

        sleep 2

        @zk.find(@base_path) { |n| puts "child: #{n.inspect}" }
      end

      Process.waitall

      event_catcher.child.should_not be_empty

      if th.join(5)
        logger.debug { "th.value: #{th.value}" }
      end


      @zk.find(@base_path) { |n| puts "parent: #{n.inspect}" } 
    end
  end
end

