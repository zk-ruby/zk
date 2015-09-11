class ClientForker
  include ZK::Logger
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
    @child_latch = Latch.new
  end

  LBORDER = ('-' * 35) << '< '
  RBORDER = ' >' << ('-' * 35) 

  def mark(thing)
    logger << "\n#{LBORDER}#{thing}#{RBORDER}\n\n"
  end

  def mark_around(thing)
    mark "#{thing}: ENTER"
    yield
  ensure
    mark "#{thing}: EXIT"
  end

  def before
    mark_around('BEFORE') do
      ZK.open(*cnx_args) do |z|
        z.rm_rf(@base_path)
        z.mkdir_p(@pids_root)
      end
    end
  end

  def tear_down
    mark_around('TEAR_DOWN') do
      @zk.close! if @zk and !@zk.closed?
      ZK.open(*cnx_args) { |z| z.rm_rf(@base_path) }
    end
  end

  def kill_child!
    return unless @pid
    Process.kill('TERM', @pid)
    pid, st = Process.wait2(@pid)
    logger.debug { "child #{@pid} exited with status: #{st.inspect}" }
  rescue Errno::ESRCH
  end

  CLEAR      = "\e[0m".freeze
  YELLOW     = "\e[33m".freeze    # Set the terminal's foreground ANSI color to yellow.

  def yellow_log_formatter()
    orig_formatter = ::Logger::Formatter.new

    proc do |s,dt,pn,msg|
      "#{CLEAR}#{YELLOW}#{orig_formatter.call(s,dt,pn,msg)}#{CLEAR}"
    end
  end

  def start_child_exit_thread(pid)
    @child_exit_thread ||= Thread.new do
      _, @stat = Process.wait2(pid)
      @child_latch.release
    end
  end

  def run
    before
    mark 'BEGIN TEST'

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
    
    @zk.create("#{@pids_root}/#{$$}", $$.to_s, :ignore => :node_exists)

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

    ZK.install_fork_hook

    mark 'FORK'

    @pid = fork do
      Thread.abort_on_exception = true

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
        create_latch.await(2) 
        unless @zk.exists?(child_pid_path)
          logger.debug { require 'pp'; PP.pp(@zk.event_handler, '') }
          raise "child pid path not created after 2 sec"
        end
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

    start_child_exit_thread(@pid)

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

    @child_latch.await(30) # if we don't get a response in 30 seconds, then we're *definately* hosed
    
    raise "Child did not exit after 30 seconds of waiting, something is very wrong" unless @stat 

  ensure
    mark "END TEST"
    kill_child!
    tear_down
  end
end

