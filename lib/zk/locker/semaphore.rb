module ZK
  module Locker
    # A semaphore implementation
    class Semaphore < LockerBase
      @default_root_node = '/_zksemaphore'.freeze unless @default_root_node

      class << self
        # the default root path we will use when a value is not given to a
        # constructor
        attr_accessor :default_root_node
      end

      def initialize(client, name, semaphore_size, root_node=nil)
        raise ZK::Exceptions::BadArguments, <<-EOMESSAGE unless semaphore_size.kind_of? Integer
          semaphore_size must be Integer, not #{semaphore_size.inspect}
        EOMESSAGE

        @semaphore_size = semaphore_size

        super(client, name, root_node || ::ZK::Locker::Semaphore.default_root_node)
      end

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
        return true   if locked?
        return false  if blocked_by_semaphore?
        true
      rescue Exceptions::NoNode
        true
      end

      def blocked_by_semaphore?
        ( blocking_locks.size >= @semaphore_size )
      end

      # @private
      def blocking_locks
        lower_lock_names
      end

      # @private
      def allowed_blocking_locks_remaining
        @semaphore_size - 1
      end

      # @private
      def lock_prefix
        SEMAPHORE_LOCK_PREFIX
      end

      def got_semaphore?
        synchronize { lock_path and not blocked_by_semaphore? }
      end
      alias_method :got_lock?, :got_semaphore?

    end # Semaphore
  end # Locker
end # ZK
