module ZK
  module Locker
    # Common code for the shared and exclusive lock implementations
    # 
    # One thing to note about this implementation is that the API unfortunately
    # __does not__ follow the convention where bang ('!') methods raise
    # exceptions when they fail. This was an oversight on the part of the
    # author, and it may be corrected sometime in the future.
    #
    class LockerBase
      include ZK::Logging
      include ZK::Exceptions

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
      #   locks will be generated, the default is Locker.default_root_lock_node
      #
      def initialize(client, name, root_lock_node=nil) 
        @zk = client
        @root_lock_node = root_lock_node || Locker.default_root_lock_node
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
        lock(true)
        yield
      ensure
        unlock
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

      # this is our current idea of whether or not we hold the lock.
      # this does not actually check the state on the server.
      #
      # @return [true,false] true if we hold the lock
      def locked?
        false|@locked
      end
      
      # @return [true] if we held the lock and this method has
      #   unlocked it successfully
      #
      # @return [false] we did not own the lock
      #
      def unlock
        if @locked
          cleanup_lock_path!
          @locked = false
          true
        else
          false # i know, i know, but be explicit
        end
      end

      # (see #unlock)
      # @deprecated the use of unlock! is deprecated and may be removed or have
      #   its semantics changed in a future release
      def unlock!
        unlock
      end

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
      def lock(blocking=false)
        raise NotImplementedError
      end

      # (see #lock)
      # @deprecated the use of lock! is deprecated and may be removed or have
      #   its semantics changed in a future release
      def lock!(blocking=false)
        lock(blocking)
      end

      # returns true if this locker is waiting to acquire lock 
      #
      # @private
      def waiting? 
        false|@waiting
      end

      # This is for people that wish to check that the assumption is correct
      # that they actually still hold the lock. (check for session interruption,
      # perhaps a lock is obtained in one method and handed to another)
      #
      # This, unlike (#locked?) will actually go and check the conditions
      # that constitute "holding the lock" with the server.
      #
      # @raise [InterruptedSession] raised when the zk session has either
      #   closed or is in an invalid state.
      #
      # @raise [LockAssertionFailedError] raised if the lock is not held
      #
      # @example 
      #   
      #   def process_jobs
      #     @lock = @zk.locker('foo')
      #
      #     @lock.with_lock do
      #       @jobs.each do |j| 
      #         @lock.assert!
      #         perform_job(j)
      #       end
      #     end
      #   end
      #
      #   def perform_job(j)
      #     puts "hah! he thinks we're workin!"
      #     sleep(60)
      #   end
      #
      def assert!
        raise LockAssertionFailedError, "have not obtained the lock yet"            unless locked?
        raise LockAssertionFailedError, "not connected"                             unless zk.connected?
        raise LockAssertionFailedError, "lock_path was #{lock_path.inspect}"        unless lock_path
        raise LockAssertionFailedError, "the lock path #{lock_path} did not exist!" unless zk.exists?(lock_path)
        raise LockAssertionFailedError, "we do not actually hold the lock"          unless got_lock?
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

        # performs the checks that (according to the recipe) mean that we hold
        # the lock. used by (#assert!)
        #
        # @private
        def got_lock?
          raise NotImplementedError
        end

        # prefix is the string that will appear in front of the sequence num,
        # defaults to 'lock'
        #
        # @private
        def create_lock_path!(prefix='lock')
          @lock_path = @zk.create("#{root_lock_path}/#{prefix}", "", :mode => :ephemeral_sequential)
          logger.debug { "got lock path #{@lock_path}" }
          @lock_path
        rescue NoNode
          create_root_path!
          retry
        end

        # @private
        def cleanup_lock_path!
          logger.debug { "removing lock path #{@lock_path}" }
          @zk.delete(@lock_path)
          @zk.delete(root_lock_path) rescue NotEmpty
          @lock_path = nil
        end
    end # LockerBase
  end # Locker
end # ZK
