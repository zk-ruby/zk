module ZK
  module Locker
    class SharedLocker < LockerBase
      include Exceptions

      # obtain a shared lock.
      #
      # @param blocking [true,false] if true we block the caller until we can obtain
      #   a lock on the resource
      # 
      # @return [true] if we're already obtained a shared lock, or if we were able to
      #   obtain the lock in non-blocking mode.
      #
      # @return [false] if we did not obtain the lock in non-blocking mode
      #
      # @return [void] if we obtained the lock in blocking mode. 
      #
      # @raise [InterruptedSession] raised when blocked waiting for a lock and
      #   the underlying client's session is interrupted. 
      #
      # @see ZK::Client::Unixisms#block_until_node_deleted more about possible execptions
      # 
      def lock!(blocking=false)
        return true if @locked
        create_lock_path!(SHARED_LOCK_PREFIX)

        if got_read_lock?      
          @locked = true
        elsif blocking
          in_waiting_status do
            block_until_read_lock!
          end
        else
          # we didn't get the lock, and we're not gonna wait around for it, so
          # clean up after ourselves
          cleanup_lock_path!
          false
        end
      end

      # @private
      def lock_number
        @lock_number ||= (lock_path and digit_from(lock_path))
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

        not_found = lambda { raise NoWriteLockFoundException }

        ary[0..my_idx].reverse.find(not_found) { |n| n =~ /^#{EXCLUSIVE_LOCK_PREFIX}/ }
      end

      # @private
      def got_read_lock?
        false if next_lowest_write_lock_num 
      rescue NoWriteLockFoundException
        true
      end

      protected
        # TODO: make this generic, can either block or non-block
        # @private
        def block_until_read_lock!
          begin
            path = [root_lock_path, next_lowest_write_lock_name].join('/')
            logger.debug { "SharedLocker#block_until_read_lock! path=#{path.inspect}" }
            @zk.block_until_node_deleted(path)
          rescue NoWriteLockFoundException
            # next_lowest_write_lock_name may raise NoWriteLockFoundException,
            # which means we should not block as we have the lock (there is nothing to wait for)
          end

          @locked = true
        end
    end # SharedLocker
  end # Locker
end # ZK
