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
      def lock(blocking=false)
        return true if synchronize { @locked }
        create_lock_path!(EXCLUSIVE_LOCK_PREFIX)

        if got_write_lock?
          synchronize { @locked = true }
        elsif blocking
          block_until_write_lock!
        else
          cleanup_lock_path!
          false
        end
      end

      # Returns the data of the owner of the lock (the node with the lowest
      # lock number). 
      #
      # @return [String] If we are currently the owner of the lock, returns
      #   {#data}. 
      #
      # @return [nil] if there is an error reading the data from the lock
      #   owner's node or if there is no current lock owner
      #
      # @note This method is subject to race conditions, especially if there's
      #   a lot of contention for the lock, or if the lock is only held for a
      #   very short time. This method will yield the most consistent results
      #   for situations where the lock is held for a long time by a single
      #   process
      #
      def owner_data
        return data if locked?
        lowest_name = lowest_exclusive_lock_node_name
        return nil unless lowest_name

        return zk.get("#{root_lock_path}/#{lowest_name}", :ignore => :no_node).first
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
      end

      private
        # the node that is next-lowest in sequence number to ours, the one we
        # watch for updates to
        def next_lowest_node
          ary = ordered_lock_children()
          my_idx = ary.index(lock_basename)

          raise WeAreTheLowestLockNumberException if my_idx == 0

          ary[(my_idx - 1)] 
        end

        # the lowest exclusive locker (the guy holding the lock)
        # nil if nobody holds the lock
        def lowest_exclusive_lock_node_name
          ary = ordered_lock_children()
          ary.first
        rescue Exceptions::NoNode 
          nil
        end

        def got_write_lock?
          ordered_lock_children.first == lock_basename
        end
        alias got_lock? got_write_lock?

        def block_until_write_lock!
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

            @node_deletion_watcher.block_until_deleted
          rescue WeAreTheLowestLockNumberException
          ensure
            logger.debug { "block_until_deleted returned" } 
          end

          @mutex.synchronize { @locked = true }
        end
    end # ExclusiveLocker
  end # Locker
end # ZK

