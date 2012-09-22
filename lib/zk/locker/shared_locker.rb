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

      # @private
      def lock_number
        lock_path and digit_from(lock_path)
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
        ary = ordered_lock_children()
        my_idx = ary.index(lock_basename)   # our idx would be 2

        ary[0..my_idx].reverse.find { |n| n.start_with?(EXCLUSIVE_LOCK_PREFIX) }.tap do |rv|
          raise NoWriteLockFoundException if rv.nil?
        end
      end

      # @private
      def got_read_lock?
        false if next_lowest_write_lock_num 
      rescue NoWriteLockFoundException
        true
      end
      alias got_lock? got_read_lock?

      private
        def lock_with_opts_hash(opts)
          create_lock_path!(SHARED_LOCK_PREFIX)

          lock_opts = LockOptions.new(opts)

          if got_read_lock?
            @mutex.synchronize { @locked = true }
          elsif lock_opts.blocking?
            block_until_read_lock!(:timeout => lock_opts.timeout)
          else
            # we didn't get the lock, and we're not gonna wait around for it, so
            # clean up after ourselves
            cleanup_lock_path!
            false
          end
        end

        def block_until_read_lock!(opts={})
          begin
            path = "#{root_lock_path}/#{next_lowest_write_lock_name}"
            logger.debug { "SharedLocker#block_until_read_lock! path=#{path.inspect}" }

            @mutex.synchronize do
              @node_deletion_watcher = NodeDeletionWatcher.new(zk, path)
              @cond.broadcast
            end

            @node_deletion_watcher.block_until_deleted(opts)
          rescue ZK::Exceptions::LockWaitTimeoutError
            # in the case of a timeout exception, we need to ensure the lock
            # path is cleaned up, since we're not interested in acquisition
            # anymore
            cleanup_lock_path!
            raise
          rescue NoWriteLockFoundException
            # next_lowest_write_lock_name may raise NoWriteLockFoundException,
            # which means we should not block as we have the lock (there is nothing to wait for)
          end

          @mutex.synchronize { @locked = true }
        end
    end # SharedLocker
  end # Locker
end # ZK
