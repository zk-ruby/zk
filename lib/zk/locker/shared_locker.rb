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

      # (see LockerBase#locked?)
      def locked?
        false|@locked
      end

      # (see LockerBase#acquirable?)
      def acquirable?
        return true if locked?
        !lock_children.any? { |n| n.start_with?(EXCLUSIVE_LOCK_PREFIX) }
      rescue Exceptions::NoNode
        true
      end

      # returns the sequence number of the next lowest write lock node
      #
      # raises NoWriteLockFoundException when there are no write nodes with a 
      # sequence less than ours
      #
      # @private
      def next_lowest_write_lock_num
        digit_from(next_lowest_write_lock_name)
      end

      # the next lowest write lock number to ours
      #
      # so if we're "read010" and the children of the lock node are:
      #
      #   %w[write008 write009 read010 read011]
      #
      # then this method will return write009
      #
      # raises NoWriteLockFoundException if there were no write nodes with an
      # index lower than ours 
      #
      # @private
      def next_lowest_write_lock_name
        lower_write_lock_names.first
      end

      # @private
      def lower_write_lock_names
        ary = ordered_lock_children()
        my_idx = ary.index(lock_basename)   # our idx would be 2

        ary[0..my_idx].reverse.select { |n| n.start_with?(EXCLUSIVE_LOCK_PREFIX) }.tap do |rv|
          raise NoWriteLockFoundException if rv.empty?
        end
      end

      # @private
      def got_read_lock?
        false if next_lowest_write_lock_num 
      rescue NoWriteLockFoundException
        true
      end
      alias got_lock? got_read_lock?

      # @private
      def blocking_locks
        lower_write_lock_names
      rescue NoWriteLockFoundException
        []
      end

      # @private
      def lock_prefix
        SHARED_LOCK_PREFIX
      end

    end # SharedLocker
  end # Locker
end # ZK
