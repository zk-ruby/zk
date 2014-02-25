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
    SEMAPHORE_LOCK_PREFIX = 'sem'.freeze

    @default_root_lock_node = '/_zklocking'.freeze unless @default_root_lock_node

    class << self
      # the default root path we will use when a value is not given to a
      # constructor
      attr_accessor :default_root_lock_node

      # Create a {SharedLocker} instance
      #
      # @param client (see LockerBase#initialize)
      # @param name (see LockerBase#initialize)
      # @return [SharedLocker]
      def shared_locker(client, name, *args)
        SharedLocker.new(client, name, *args)
      end

      # Create an {ExclusiveLocker} instance
      #
      # @param client (see LockerBase#initialize)
      # @param name (see LockerBase#initialize)
      # @return [ExclusiveLocker]
      def exclusive_locker(client, name, *args)
        ExclusiveLocker.new(client, name, *args)
      end

      # Create a {Semaphore} instance
      #
      # @param client (see Semaphore#initialize)
      # @param name (see Semaphore#initialize)
      # @param semaphore_size (see Semaphore#initialize)
      # @return [Semaphore]
      def semaphore(client, name, semaphore_size, *args)
        Semaphore.new(client, name, semaphore_size, *args)
      end

      # Clean up dead locker directories. There are situations (particularly
      # session expiration) where a lock's directory will never be cleaned up.
      #
      # It is intened to be run periodically (perhaps from cron).
      #
      #
      # This implementation goes through each lock directory and attempts to
      # acquire an exclusive lock. If the lock is acquired then when it unlocks
      # it will remove the locker directory. This is safe because the unlock 
      # code is designed to deal with the inherent race conditions.
      #
      # @example
      #   
      #   ZK.open do |zk|
      #     ZK::Locker.cleanup!(zk)
      #   end
      #
      # @param client [ZK::Client::Threaded] the client connection to use
      #
      # @param root_lock_node [String] if given, use an alternate root lock node to base
      #   each Locker's path on. You probably don't need to touch this. Uses
      #   {Locker.default_root_lock_node} by default (if value is nil)
      #
      def cleanup(client, root_lock_node=default_root_lock_node)
        client.children(root_lock_node).each do |name|
          exclusive_locker(client, name, root_lock_node).tap do |locker|
            locker.unlock if locker.lock
          end
        end
      end
    end
    
    # @private
    class NoWriteLockFoundException < StandardError
    end

    # @private
    class WeAreTheLowestLockNumberException < StandardError
    end
  end # Locker
end # ZK

require 'zk/locker/lock_options'
require 'zk/locker/locker_base'
require 'zk/locker/shared_locker'
require 'zk/locker/exclusive_locker'
require 'zk/locker/semaphore'

