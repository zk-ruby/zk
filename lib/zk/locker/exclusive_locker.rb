module ZK
  module Locker
    # An exclusive lock implementation
    #
    # If the name 'dingus' is given, then in the case of an exclusive lock, the
    # algorithm works like:
    #
    # * lock_path = `zk.create("/_zklocking/dingus/ex", :sequential => true, :ephemeral => true)`
    # * extract the digit from the lock path
    # * of all the children under '/_zklocking/dingus', do we have the lowest digit?
    #   * __yes__: then we hold the lock, if we're non-blocking, return true
    #   * __no__: is the lock blocking?
    #       * __yes__: then set a watch on the next-to-lowest node and sleep the current thread until that node has been deleted
    #       * __no__: return false, you lose
    # 
    class ExclusiveLocker < LockerBase
      # (see LockerBase#lock)
      # obtain an exclusive lock.
      #
      def lock(opts={})
        super
      end

      # (see LockerBase#assert!)
      #
      # checks that we:
      #
      # * we have obtained the lock (i.e. {#locked?} is true)
      # * have a lock path
      # * our lock path still exists
      # * there are no locks, _exclusive or shared_, with lower numbers than ours
      # 
      def assert!
        super
      end

      # (see LockerBase#acquirable?)
      def acquirable?
        return true if locked? 
        stat = zk.stat(root_lock_path)
        !stat.exists? or stat.num_children == 0
      rescue Exceptions::NoNode   # XXX: is this ever hit? stat shouldn't raise
        true
      end

      private
        def lock_with_opts_hash(opts)
          create_lock_path!(EXCLUSIVE_LOCK_PREFIX)

          lock_opts = LockOptions.new(opts)

          if got_write_lock?
            @mutex.synchronize { @locked = true }
          elsif lock_opts.blocking?
            block_until_write_lock!(:timeout => lock_opts.timeout)
          else
            cleanup_lock_path!
            false
          end
        end

        # the node that is next-lowest in sequence number to ours, the one we
        # watch for updates to
        def next_lowest_node
          ary = ordered_lock_children()
          my_idx = ary.index(lock_basename)

          raise WeAreTheLowestLockNumberException if my_idx == 0

          ary[(my_idx - 1)] 
        end

        def got_write_lock?
          ordered_lock_children.first == lock_basename
        end
        alias got_lock? got_write_lock?

        def block_until_write_lock!(opts={})
          begin
            path = "#{root_lock_path}/#{next_lowest_node}"
            logger.debug { "#{self.class}##{__method__} path=#{path.inspect}" }

            @mutex.synchronize do
              logger.debug { "assigning the @node_deletion_watcher" }
              @node_deletion_watcher = NodeDeletionWatcher.new(zk, path)
              logger.debug { "broadcasting" }
              @cond.broadcast
            end

            logger.debug { "calling block_until_deleted" }
            Thread.pass

            @node_deletion_watcher.block_until_deleted(opts)
          rescue WeAreTheLowestLockNumberException
          rescue ZK::Exceptions::LockWaitTimeoutError
            # in the case of a timeout exception, we need to ensure the lock
            # path is cleaned up, since we're not interested in acquisition
            # anymore
            logger.warn { "got ZK::Exceptions::LockWaitTimeoutError, cleaning up lock path" }
            cleanup_lock_path!
            raise
          ensure
            logger.debug { "block_until_deleted returned" } 
          end

          @mutex.synchronize { @locked = true }
        end
    end # ExclusiveLocker
  end # Locker
end # ZK

