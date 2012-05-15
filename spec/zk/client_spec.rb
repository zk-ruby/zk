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

  describe :forked, :fork_required => true, :rbx => :broken do
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

    it %[should deliver callbacks in the child], :fork => true do
      logger.debug { "Process.pid of parent: #{Process.pid}" }

      @zk = ZK.new do |z|
        z.on_connected do
          logger.debug { "on_connected fired, writing pid to path #{@pids_root}/#{$$}" }
          begin
            z.create("#{@pids_root}/#{Process.pid}", Process.pid.to_s)
          rescue ZK::Exceptions::NodeExists
          end
        end
      end

      @parent_pid = $$
      
      @zk.create("#{@pids_root}/#{$$}", $$.to_s)

      event_catcher = EventCatcher.new

      @zk.register(@pids_root) do |event|
        if event.node_child?
          event_catcher << event
        else
          @zk.children(@pids_root, :watch => true)
        end
      end

      logger.debug { "parent watching for children on #{@pids_root}" }
      @zk.children(@pids_root, :watch => true)  # side-effect, register watch

      @pid = fork do
        GC.start

        Zookeeper.debug_level = 4
        @zk.reopen
        $stderr.puts "Reopen returned"
        @zk.wait_until_connected
        $stderr.puts "we are connected"

        child_pid_path = "#{@pids_root}/#{$$}"

        create_latch = Zookeeper::Latch.new

        create_sub = @zk.register(child_pid_path) do |event|
          if event.node_created?
            logger.debug { "got created event, releasing create_latch" }
            create_latch.release
          else
            if @zk.exists?(child_pid_path, :watch => true)
              logger.debug { "created behind our backs, releasing create_latch" }
              create_latch.release 
            end
          end
        end

        if @zk.exists?(child_pid_path, :watch => true)
          logger.debug { "woot! #{child_pid_path} exists!" }
          create_sub.unregister
        else
          logger.debug { "awaiting the create_latch to release" }
          create_latch.await
        end

        logger.debug { "now testing for delete event totally created in child" }

        delete_latch = Zookeeper::Latch.new

        delete_event = nil

        delete_sub = @zk.register(child_pid_path) do |event|
          if event.node_deleted?
            delete_event = event
            logger.debug { "child got delete event on #{child_pid_path}" }
            delete_latch.release
          else
            unless @zk.exists?(child_pid_path, :watch => true)
              logger.debug { "child: someone deleted #{child_pid_path} behind our back" }
              delete_latch.release 
            end
          end
        end

        @zk.exists?(child_pid_path, :watch => true)

        @zk.delete(child_pid_path)

        logger.debug { "awaiting deletion event notification" }
        delete_latch.await unless delete_event

        logger.debug { "deletion event: #{delete_event}" }

        if delete_event
          exit! 0
        else
          exit! 1
        end
      end # fork()

      # replicates deletion watcher inside child
      child_pid_path = "#{@pids_root}/#{@pid}"

      delete_latch = Latch.new

      delete_sub = @zk.register(child_pid_path) do |event|
        if event.node_deleted?
          logger.debug { "parent got delete event on #{child_pid_path}" }
          delete_latch.release
        else
          unless @zk.exists?(child_pid_path, :watch => true)
            logger.debug { "child: someone deleted #{child_pid_path} behind our back" }
            delete_latch.release
          end
        end
      end

      delete_latch.await if @zk.exists?(child_pid_path, :watch => true)

      begin
        _, stat = Process.wait2(@pid)

        stat.should_not be_signaled
        stat.should be_exited
        stat.should be_success
      rescue Errno::ECHILD
        $stderr.puts "got ECHILD in parent"
      end


    end # should deliver callbacks in the child
  end # forked
end # ZK::Client::Threaded

