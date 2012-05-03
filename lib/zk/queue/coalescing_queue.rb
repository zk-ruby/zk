module ZK
  module Queue
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
    #   * create paths `/_zk/queue/coalesce/<task_name>/{t00,t01,t02,t03,t04,t05}`
    #   * each makes a note of the path in the 'job'
    #
    # * worker is notified of "work to do"    
    #   * locks the queue (exclusive to workers, not submitters)
    #   * deletes all paths including `t05`
    #   * unlocks the queue
    #   * calls user supplied block with `/_zk/queue/coalesce/<task_name>/t05` as the last path to do work on
    #
    class CoalescingQueue
    end
  end # Queue
end # ZK

