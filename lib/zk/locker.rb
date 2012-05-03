module ZK
  # This module contains implementations of the locking primitives described in
  # [the ZooKeeper recipes][recipes] that allow a user to obtain cluster-wide
  # global locks (with both blocking and non-blocking semantics).  One
  # important (and attractive) attribute of these locks is that __they are
  # automatically released when the connection closes__. You never have to
  # worry about a stale lock mucking up coordination because some process was
  # killed and couldn't clean up after itself.
  #
  # There are both shared and exclusive lock implementations.
  #
  # The implementation is fairly true to the description in the [recipes][], and
  # the key is generated using a combination of the name provided, and a
  # `root_lock_node` path whose default value is `/_zklocking`. If you look
  # below at the 'Key path creation' example, you'll see that we do a very
  # simple escaping of the name given. There was a distinct tradeoff to be made
  # between making the locks easy to debug in zookeeper and making them more
  # collision tolerant. If the key naming causes issues, please [file a bug] and
  # we'll try to work out a solution (hearing about use cases is incredibly helpful
  # in guiding development).
  #
  # If you're interested in how the algorithm works, have a look at
  # {ZK::Locker::ExclusiveLocker}'s documentation.
  #
  # [recipes]: http://zookeeper.apache.org/doc/r3.3.5/recipes.html#sc_recipes_Locks
  # [file a bug]: https://github.com/slyphon/zk/issues
  #
  # ## Shared/Exclusive lock interaction ##
  #
  # The shared and exclusive locks can be used to create traditional read/write locks,
  # and are designed to be fair in terms of ordering. Given the following children
  # of a given lock node (where 'sh' is shared, and 'ex' is exclusive)
  #
  #     [ex00, sh01, sh02, sh03, ex04, ex05, sh06, sh07]
  #
  # Assuming all of these locks are blocking, the following is how the callers would 
  # obtain the lock
  #
  # * `ex00` holds the lock, everyone else is blocked
  # * `ex00` releases the lock 
  #   * `[sh01, sh02, sh03]` all unblock and hold a shared lock
  #   * `[ex04, ...]` are blocked
  # * `[sh01, sh02, sh03]` all release
  #   * `ex04` is unblocked, holds the lock
  #   * `[ex05, ...]` are blocked
  # * `ex04` releases the lock
  #   * `ex05` unblocks, holds the lock
  #   * `[sh06, sh07]` are blocked
  # * `ex05` releases the lock
  #   * `[sh06, sh07]` are unblocked, hold the lock
  #
  # 
  # In this way, the locks are fair-queued (FIFO), and shared locks will not
  # starve exclusive locks (all lock types have the same priority)
  #
  # @example Key path creation
  #
  #   "#{root_lock_node}/#{name.gsub('/', '__')}/#{shared_or_exclusive_prefix}"
  #  
  # @note These lock instances are _not_ safe for use across threads. If you
  #   want to use the same Locker instance between threads, it is your
  #   responsibility to synchronize operations.
  #
  # @note Lockers are *instances* that hold the lock. A single connection may
  #   have many instances trying to lock the same path and only *one* (in the
  #   case of an ExclusiveLocker) will hold the lock.
  #
  # @example Creating locks directly from a client instance
  #
  #   # this same example would work for zk.shared_locker('key_name') only
  #   # the lock returned would be a shared lock, instead of an exclusive lock
  #
  #   ex_locker = zk.locker('key_name')
  #
  #   begin
  #     if ex_locker.lock!
  #       # do something while holding lock
  #     else
  #       raise "Oh noes, we didn't get teh lock!"
  #     end
  #   ensure
  #     ex_locker.unlock!
  #   end
  #
  # @example Creating a blocking lock around a cluster-wide critical section
  #
  #   zk.with_lock('key_name') do       # this will block us until we get the lock
  #
  #     # this is the critical section
  #
  #   end
  module Locker
    SHARED_LOCK_PREFIX  = 'sh'.freeze
    EXCLUSIVE_LOCK_PREFIX = 'ex'.freeze

    # Create a {SharedLocker} instance
    #
    # @param client (see LockerBase#initialize)
    # @param name (see LockerBase#initialize)
    # @return [SharedLocker]
    def self.shared_locker(client, name, *args)
      SharedLocker.new(client, name, *args)
    end

    # Create an {ExclusiveLocker} instance
    #
    # @param client (see LockerBase#initialize)
    # @param name (see LockerBase#initialize)
    # @return [ExclusiveLocker]
    def self.exclusive_locker(client, name, *args)
      ExclusiveLocker.new(client, name, *args)
    end
    
    # @private
    class NoWriteLockFoundException < StandardError
    end

    # @private
    class WeAreTheLowestLockNumberException < StandardError
    end

    # Common code for the shared and exclusive lock implementations
    # 
    # One thing to note about this implementation is that the API unfortunately
    # __does not__ follow the convention where bang ('!') methods raise
    # exceptions when they fail. This was an oversight on the part of the
    # author, and it may be corrected sometime in the future.
    #
    class LockerBase
      include ZK::Logging

      # @private
      attr_accessor :zk

      # our absolute lock node path
      #
      # @example 
      #
      #   '/_zklocking/foobar/__blah/lock000000007'
      #
      # @return [String]
      attr_reader :lock_path

      # @private
      attr_reader :root_lock_path

      # Extracts the integer from the zero-padded sequential lock path
      #
      # @return [Integer] our digit
      # @private
      def self.digit_from_lock_path(path)
        path[/0*(\d+)$/, 1].to_i
      end

      # Create a new lock instance.
      #
      # @param [Client::Threaded] client a client instance
      #
      # @param [String] name Unique name that will be used to generate a key.
      #   All instances created with the same `root_lock_node` and `name` will be
      #   holding the same lock.
      #
      # @param [String] root_lock_node the root path on the server under which all
      #   locks will be generated
      #
      def initialize(client, name, root_lock_node = "/_zklocking") 
        @zk = client
        @root_lock_node = root_lock_node
        @path = name
        @locked = false
        @waiting = false
        @root_lock_path = "#{@root_lock_node}/#{@path.gsub("/", "__")}"
      end
      
      # block caller until lock is aquired, then yield
      #
      # there is no non-blocking version of this method
      #
      def with_lock
        lock!(true)
        yield
      ensure
        unlock!
      end

      # the basename of our lock path
      #
      # @example
      #
      #   > locker.lock_path
      #   # => '/_zklocking/foobar/__blah/lock000000007'
      #   > locker.lock_basename
      #   # => 'lock000000007'
      #
      # @return [nil] if lock_path is not set
      # @return [String] last path component of our lock path
      def lock_basename
        lock_path and File.basename(lock_path)
      end

      # @return [true,false] true if we hold the lock
      def locked?
        false|@locked
      end
      
      # @return [true] if we held the lock and this method has
      #   unlocked it successfully
      #
      # @return [false] we did not own the lock
      #
      def unlock!
        if @locked
          cleanup_lock_path!
          @locked = false
          true
        else
          false # i know, i know, but be explicit
        end
      end

      # returns true if this locker is waiting to acquire lock 
      #
      # @private
      def waiting? 
        false|@waiting
      end

      protected 
        # @private
        def in_waiting_status
          w, @waiting = @waiting, true
          yield
        ensure
          @waiting = w
        end

        # @private
        def digit_from(path)
          self.class.digit_from_lock_path(path)
        end

        # @private
        def lock_children(watch=false)
          @zk.children(root_lock_path, :watch => watch)
        end

        # @private
        def ordered_lock_children(watch=false)
          lock_children(watch).tap do |ary|
            ary.sort! { |a,b| digit_from(a) <=> digit_from(b) }
          end
        end

        # @private
        def create_root_path!
          @zk.mkdir_p(@root_lock_path)
        end

        # prefix is the string that will appear in front of the sequence num,
        # defaults to 'lock'
        #
        # @private
        def create_lock_path!(prefix='lock')
          @lock_path = @zk.create("#{root_lock_path}/#{prefix}", "", :mode => :ephemeral_sequential)
          logger.debug { "got lock path #{@lock_path}" }
          @lock_path
        rescue Exceptions::NoNode
          create_root_path!
          retry
        end

        # @private
        def cleanup_lock_path!
          logger.debug { "removing lock path #{@lock_path}" }
          @zk.delete(@lock_path)
          @zk.delete(root_lock_path) rescue Exceptions::NotEmpty
        end
    end

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

    # An exclusive lock implementation
    #
    # If the name 'dingus' is given, then in the case of an exclusive lock, the
    # algorithm works like:
    #
    # * lock_path = `zk.create("/_zklocking/dingus/ex", :sequential => true, :ephemeral => true)`
    # * extract the digit from the lock path
    # * of all the children under '/_zklocking/dingus', do we have the lowest digit?
    #   * __yes__: then we hold the lock
    #   * __no__: is the lock blocking?
    #       * __yes__: then set a watch on the next-to-lowest node and sleep the current thread until that node has been deleted
    #       * __no__: return false, you're done
    # 
    class ExclusiveLocker < LockerBase
      # obtain an exclusive lock.
      #
      # @param blocking (see SharedLocker#lock!)
      # @return (see SharedLocker#lock!)
      #
      # @raise [InterruptedSession] raised when blocked waiting for a lock and
      #   the underlying client's session is interrupted. 
      #
      # @see ZK::Client::Unixisms#block_until_node_deleted more about possible execptions
      # 
      def lock!(blocking=false)
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
  end   # SharedLocker
end     # ZooKeeper

