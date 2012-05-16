class ClientForker
  include ZK::Logging
  attr_reader :base_path, :cnx_args, :stat

  def self.run(cnx_args, base_path)
    cf = new(cnx_args, base_path)
    cf.run
    yield cf
  end

  def initialize(cnx_args, base_path)
    @cnx_args  = cnx_args
    @base_path = base_path
    @pids_root = "#{@base_path}/pid"
  end

  def before
    ZK.open(*cnx_args) do |z|
      z.rm_rf(@base_path)
      z.mkdir_p(@pids_root)
    end
  end

  def tear_down
    @zk.rm_rf(@base_path)
    @zk.close! unless @zk.closed?
  end

  def kill_child!
    return unless @pid
    Process.kill('TERM', @pid)
    pid, st = Process.wait2(@pid)
    logger.debug { "child #{@pid} exited with status: #{st.inspect}" }
  rescue Errno::ESRCH
  end

  def run
    before

    logger.debug { "Process.pid of parent: #{Process.pid}" }

    @zk = ZK.new(*cnx_args) do |z|
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
      @zk.reopen
      @zk.wait_until_connected

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
    end # forked child

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

    _, @stat = Process.wait2(@pid)

#     $stderr.puts "#{@pid} exited with status: #{stat.inspect}"
  ensure
    kill_child!
    tear_down
  end
end

