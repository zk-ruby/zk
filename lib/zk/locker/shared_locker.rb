module ZK
  module Locker
    class SharedLocker < LockerBase
      include Exceptions

      # (see LockerBase#lock)
      # obtain a shared lock.
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
      # * there are no exclusive locks with lower numbers than ours
      # 
      def assert!
        super
      end

      # (see LockerBase#acquirable?)
      def acquirable?
        return true if locked?
        blocking_locks.empty?
      rescue Exceptions::NoNode
        true
      end

      # @private
      def lower_write_lock_names
        lower_lock_names.select do |lock|
          lock.start_with?(EXCLUSIVE_LOCK_PREFIX)
        end
      end
      alias :blocking_locks :lower_write_lock_names

      # @private
      def lock_prefix
        SHARED_LOCK_PREFIX
      end

    end # SharedLocker
  end # Locker
end # ZK
