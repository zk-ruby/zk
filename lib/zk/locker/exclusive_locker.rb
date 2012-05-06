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
        return true if @locked
        create_lock_path!(EXCLUSIVE_LOCK_PREFIX)

        if got_write_lock?
          @locked = true
        elsif blocking
          in_waiting_status do
            block_until_write_lock!
          end
        else
          cleanup_lock_path!
          false
        end
      end

      # (see LockerBase#assert!)
      #
      def assert!
        assert_locked!
        unless zk.connected? and @lock_path and zk.exists?(@lock_path) and got_read_lock?
        end
      end

      protected
        # the node that is next-lowest in sequence number to ours, the one we
        # watch for updates to
        # @private
        def next_lowest_node
          ary = ordered_lock_children()
          my_idx = ary.index(lock_basename)

          raise WeAreTheLowestLockNumberException if my_idx == 0

          ary[(my_idx - 1)] 
        end

        # @private
        def got_write_lock?
          ordered_lock_children.first == lock_basename
        end
        alias got_lock? got_write_lock?

        # @private
        def block_until_write_lock!
          begin
            path = [root_lock_path, next_lowest_node].join('/')
            logger.debug { "SharedLocker#block_until_write_lock! path=#{path.inspect}" }
            @zk.block_until_node_deleted(path)
          rescue WeAreTheLowestLockNumberException
          end

          @locked = true
        end
    end # ExclusiveLocker
  end # Locker
end # ZK

