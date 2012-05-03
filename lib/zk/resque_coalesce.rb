module ZK
  # An experimental implementation of a queue that is designed for the
  # following use-case (built around a task queue like Resque):
  #
  # * multiple nodes in a cluster will 'publish' when a task needs to be completed
  # * a single worker will listen for messages and take *the last one* before
  #   peforming work, ignoring earlier ones
  #
  # workflow looks like:
  #
  # * nodes: n1, n2, n3 all submit jobs
  #   * create paths `/_zk/rq_coalesce/<task_name>/{t00,t01,t02,t03,t04,t05}`
  #   * each makes a note of the path in the 'job'
  #
  # * worker is notified of "work to do"    
  #   * locks the queue (exclusive to workers, not submitters)
  #   * deletes all paths including `t05`
  #   * unlocks the queue
  #   * calls user supplied block with `/_zk/rq_coalesce/<task_name>/t05` as the last path to do work on
  #
  class ResqueCoalesce
    include ZK::Logging

    PREFIX = 't'

    @default_root_path = '/_zk/rq_coalesce'.freeze unless @default_root_path

    class << self
      attr_accessor :default_root_path
    end

    # does a simple substitution, replacing invalid characters with '_'
    def self.sanitize(task_name)
      task_name.tr('/', '_')
    end
    
    attr_reader :zk, :task_path, :root_path, :task_name, :seq_template

    def initialize(zk, task_name, opts={})
      @zk = zk
      @task_name = self.class.sanitize(task_name)
      @root_path = opts.fetch(:root_path, self.class.default_root_path)

      @task_path = File.join(@root_path, @task_name)
      @seq_template = File.join(@task_path, PREFIX)
    end

    # Submits a request for some unit of work to be done. This specific task
    # may or may not be done, but you are guaranteed that the worker will perform
    # a job in the next iteration.
    #
    # @note All participants must use the same values for `task_name` and `root_path`
    #
    # @return [String] a unique id that will be used to deduplicate requests on
    #   the worker side
    #
    # @param [String] task_name name of the task we are trying to coalesce
    #
    # @option opts [String] :root_path (ResqueCoalesce.default_root_path) the
    #   root under which we should create our unique id. 
    #
    def submit
      zk.mkdir_p(task_path)
      zk.create(seq_template, :sequence => true)
    end

    # return the current (sorted) task names 
    def peek
      zk.children(task_path).sort
    end

    # unique_id is a full path like "/#{root_path}/#{task_name}/t0003"
    def maybe_run_job(unique_id)
      t_path, req_name = File.split(unique_id)

      unless t_path == @task_path
        raise ArgumentError, "that unique_id #{unique_id.inspect} isn't for us, task_path: #{task_path}"
      end

      synchronize_queue do
        tasklist = peek()

        logger.debug { "got a tasklist: #{tasklist.inspect}" }

        unless tasklist.last == req_name
          logger.debug { "aww, we fail, not the last job" }
          return false 
        end

        logger.debug { "ooh! we're the last job, first we clean up" }
        
        # we run the job, but first we clean up
        tasklist.each do |n|
          zk.delete(File.join(task_path, n))
        end
      end

      logger.debug { "we run #{unique_id}! (hooraj!)" }

      # call the block after cleaning up and releasing queue lock
      yield

      true
    end

    def synchronize_queue
      zk.with_lock(@task_path) do
        yield
      end
    end

  end # Queue
end # ZK

