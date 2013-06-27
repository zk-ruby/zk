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

        # @private
        def lock_prefix
          EXCLUSIVE_LOCK_PREFIX
        end

        # @private
        def blocking_locks
          lower_lock_names
        end

    end # ExclusiveLocker
  end # Locker
end # ZK

