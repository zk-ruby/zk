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
      include ZK::Logger
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

        @path           = name
        @locked         = false
        @waiting        = false
        @lock_path      = nil
        @parent_stat    = nil
        @root_lock_path = "#{@root_lock_node}/#{@path.gsub("/", "__")}"

        @mutex  = Monitor.new
        @cond   = @mutex.new_cond
        @node_deletion_watcher = nil
      end
      
      # block caller until lock is aquired, then yield
      #
      # there is no non-blocking version of this method
      #
      # @yield [lock] calls the block with the lock instance when acquired
      #
      # @option opts [Numeric,true] :wait (nil) if non-nil, the amount of time to
      #   wait for the lock to be acquired. since with_lock is only blocking,
      #   `false` isn't a valid option. `true` is ignored (as it is the default).
      #   If a Numeric (float or integer) option is given, maximum amount of time
      #   to wait for lock acquisition.
      #
      # @raise [LockWaitTimeoutError] if the :wait timeout is exceeded
      # @raise [ArgumentError] if :wait is false (since you can't do non-blocking)
      def with_lock(opts={})
        if opts[:wait].kind_of?(FalseClass)
          raise ArgumentError, ":wait cannot be false, with_lock is only used in blocking mode"
        end

        opts = { :wait => true }.merge(opts)
        lock(opts)
        yield self
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
        synchronize { lock_path and File.basename(lock_path) }
      end

      # @private
      def lock_number
        synchronize { lock_path and digit_from(lock_path) }
      end

      # returns our current idea of whether or not we hold the lock, which does
      # not actually check the state on the server.
      #
      # The reason for the equivocation around _thinking_ we hold the lock is
      # to contrast our current state and the actual state on the server. If you
      # want to make double-triple certain of the state of the lock, use {#assert!}
      #
      # @return [true] if we hold the lock
      # @return [false] if we don't hold the lock
      #
      def locked?
        synchronize { !!@locked }
      end

      # * If this instance holds the lock {#locked? is true} we return true (as
      #   we have already succeeded in acquiring the lock)
      # * If this instance doesn't hold the lock, we'll do a check on the server 
      #   to see if there are any participants _who hold the lock and would
      #   prevent us from acquiring the lock_. 
      #   * If this instance could acquire the lock we will return true. 
      #   * If another client would prevent us from acquiring the lock, we return false. 
      #
      # @note It should be obvious, but there is no way to guarantee that
      #   between the time this method checks the server and taking any action to
      #   acquire the lock, another client may grab the lock before us (or
      #   converseley, another client may release the lock). This is simply meant
      #   as an advisory, and may be useful in some cases.
      #
      def acquirable?
        raise NotImplementedError
      end
      
      # @return [true] if we held the lock and this method has
      #   unlocked it successfully
      #
      # @return [false] if we did not own the lock.
      #
      # @note There is more than one way you might not "own the lock" 
      #   see [issue #34](https://github.com/slyphon/zk/issues/34)
      #
      def unlock
        rval = false
        @mutex.synchronize do
          if @locked
            logger.debug { "unlocking" }
            rval = cleanup_lock_path!
            @locked = false
            @node_deletion_watcher = nil
            @cond.broadcast
          end
        end
        rval
      end

      # (see #unlock)
      # @deprecated the use of unlock! is deprecated and may be removed or have
      #   its semantics changed in a future release
      def unlock!
        unlock
      end

      # @overload lock(blocking=false)
      #   @param blocking [true,false] if true we block the caller until we can
      #     obtain a lock on the resource
      #   
      #   @deprecated in favor of the options hash style
      #
      # @overload lock(opts={})
      #   @option opts [true,false,Numeric] :wait (false) If true we block the
      #     caller until we obtain a lock on the resource. If false, we do not
      #     block. If a Numeric, the number of seconds we should wait for the
      #     lock to be acquired. Will raise LockWaitTimeoutError if we exceed
      #     the timeout.
      #
      #   @since 1.7
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
      # @raise [LockWaitTimeoutError] if the given timeout is exceeded waiting
      #   for the lock to be acquired
      #
      # @see ZK::Client::Unixisms#block_until_node_deleted for more about possible execptions
      def lock(opts={})
        return true if @mutex.synchronize { @locked }

        case opts
        when TrueClass, FalseClass      # old style boolean argument
          opts = { :wait => opts }
        end

        lock_with_opts_hash(opts)
      end

      # delegates to {#lock}
      #
      # @deprecated the use of lock! is deprecated and may be removed or have
      #   its semantics changed in a future release
      def lock!(opts={})
        lock(opts)
      end

      # returns true if this locker is waiting to acquire lock 
      # this should be used in tests only. 
      #
      # @private
      def waiting? 
        @mutex.synchronize do
          !!(@node_deletion_watcher and @node_deletion_watcher.blocked?)
        end
      end

      # blocks the caller until this lock is blocked
      # @private
      def wait_until_blocked(timeout=nil)
        time_to_stop = timeout ? (Time.now + timeout) : nil

        @mutex.synchronize do
          if @node_deletion_watcher
            logger.debug { "@node_deletion_watcher already assigned, not waiting" }
          else
            logger.debug { "going to wait up to #{timeout} sec for a @node_deletion_watcher to be assigned" }

            @cond.wait(timeout) 
            raise "Timeout waiting for @node_deletion_watcher" unless @node_deletion_watcher
          end
        end
        logger.debug { "ok, @node_deletion_watcher: #{@node_deletion_watcher}, going to call wait_until_blocked" }

        @node_deletion_watcher.wait_until_blocked(timeout)
      end

      # This is for users who wish to check that the assumption is correct
      # that they actually still hold the lock. (check for session interruption,
      # perhaps a lock is obtained in one method and handed to another)
      #
      # This, unlike {#locked?} will actually go and check the conditions
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
        @mutex.synchronize do
          raise LockAssertionFailedError, "have not obtained the lock yet"            unless locked?
          raise LockAssertionFailedError, "lock_path was #{lock_path.inspect}"        unless lock_path
          raise LockAssertionFailedError, "the lock path #{lock_path} did not exist!" unless zk.exists?(lock_path)
          raise LockAssertionFailedError, "the parent node was replaced!"             unless root_lock_path_same?
          raise LockAssertionFailedError, "we do not actually hold the lock"          unless got_lock?
        end
      end

      def assert
        assert!
        true
      rescue LockAssertionFailedError
        false
      end

      private
        def synchronize
          @mutex.synchronize { yield }
        end

        def digit_from(path)
          self.class.digit_from_lock_path(path)
        end

        def lock_children(watch=false)
          zk.children(root_lock_path, :watch => watch)
        end

        def ordered_lock_children(watch=false)
          lock_children(watch).tap do |ary|
            ary.sort! { |a,b| digit_from(a) <=> digit_from(b) }
          end
        end

        # root_lock_path is /_zklocking/foobar
        #
        def create_root_path!
          zk.mkdir_p(@root_lock_path)
        rescue NoNode
          retry
        end

        # prefix is the string that will appear in front of the sequence num,
        # defaults to 'lock'
        #
        # this method also saves the stat of root_lock_path at the time of creation
        # to ensure we don't accidentally remove a lock we don't own. see 
        # [rule #34](https://github.com/slyphon/zk/issues/34)...er, *issue* #34.
        #
        def create_lock_path!(prefix='lock')
          @mutex.synchronize do
            unless lock_path_exists?
              @lock_path = @zk.create("#{root_lock_path}/#{prefix}", :mode => :ephemeral_sequential)
              @parent_stat = @zk.stat(root_lock_path)
            end
          end

          logger.debug { "got lock path #{@lock_path}" }
          @lock_path
        rescue NoNode
          create_root_path!
          retry
        end

        # if we previously had a lock path, check if it still exists
        #
        def lock_path_exists?
          @mutex.synchronize do
            return false unless @lock_path
            return false unless root_lock_path_same?
            zk.exists?(@lock_path)
          end
        end

        # if the root_lock_path has the same stat .ctime as the one
        # we cached when we created our lock path, then we can be sure
        # that we actually own the lock_path 
        #
        # see [issue #34](https://github.com/slyphon/zk/issues/34)
        #
        def root_lock_path_same?
          @mutex.synchronize do
            return false unless @parent_stat

            cur_stat = zk.stat(root_lock_path)  
            cur_stat.exists? and (cur_stat.ctime == @parent_stat.ctime)
          end
        end

        # we make a best-effort to clean up, this case is rife with race
        # conditions if there is a lot of contention for the locks, so if we
        # can't remove a path or if that path happens to not be empty we figure
        # either we got pwned or that someone else will run this same method
        # later and get to it
        #
        def cleanup_lock_path!
          rval = false

          @mutex.synchronize do
            if root_lock_path_same?
              logger.debug { "removing lock path #{@lock_path}" }

              zk.delete(@lock_path, :ignore => :no_node)
              zk.delete(root_lock_path, :ignore => [:not_empty, :no_node])
              rval = true
            end

            @lock_path = @parent_stat = nil
          end

          rval
        end

        # @private
        def lower_lock_names(watch=false)
          olc = ordered_lock_children(watch)
          return olc unless lock_path

          olc.select do |lock|
            digit_from(lock) < lock_number
          end
        end

        # for write locks & semaphores, this will be all locks lower than us
        # for read locks, this will be all write-locks lower than us.
        # @return [Array] an array of string node paths
        def blocking_locks
          raise NotImplementedError
        end

        def lock_prefix
          raise NotImplementedError
        end

        # performs the checks that (according to the recipe) mean that we hold
        # the lock. used by (#assert!)
        #
        def got_lock?
          lock_path and blocking_locks.empty?
        end

        # for write locks & read locks, this will be zero since #blocking_locks
        # accounts for all locks that could block at all.
        # for semaphores, this is one less than the semaphore size.
        # @private
        # @returns [Integer]
        def allowed_blocking_locks_remaining
          0
        end

        def blocking_locks_full_paths
          blocking_locks.map { |partial| "#{root_lock_path}/#{partial}"}
        end

        def lock_with_opts_hash(opts)
          create_lock_path!(lock_prefix)

          lock_opts = LockOptions.new(opts)

          if got_lock? or (lock_opts.blocking? and block_until_lock!(:timeout => lock_opts.timeout))
            @mutex.synchronize { @locked = true }
          else
            false
          end
        ensure
          cleanup_lock_path! unless @mutex.synchronize { @locked }
        end

        def block_until_lock!(opts={})
          paths = blocking_locks_full_paths

          logger.debug { "#{self.class}\##{__method__} paths=#{paths.inspect}" }

          @mutex.synchronize do
            logger.debug { "assigning the @node_deletion_watcher" }
            ndw_options = {:threshold => allowed_blocking_locks_remaining}
            @node_deletion_watcher = NodeDeletionWatcher.new(zk, paths, ndw_options)
            logger.debug { "broadcasting" }
            @cond.broadcast
          end

          logger.debug { "calling block_until_deleted" }
          Thread.pass

          @node_deletion_watcher.block_until_deleted(opts)
          true
        end
    end # LockerBase
  end # Locker
end # ZK
