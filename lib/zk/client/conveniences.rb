module ZK
  module Client
    # EXTENSIONS
    #
    # convenience methods for dealing with zookeeper (rm -rf, mkdir -p, etc)
    module Conveniences
      # Queue an operation to be run on an internal threadpool. You may either
      # provide an object that responds_to?(:call) or pass a block. There is no
      # mechanism for retrieving the result of the operation, it is purely
      # fire-and-forget, so the user is expected to make arrangements for this in
      # their code. 
      #
      # An ArgumentError will be raised if +callable+ does not <tt>respond_to?(:call)</tt>
      #
      # @param [#call] callable an object that `respond_to?(:call)`, takes
      #   precedence over a given block
      #
      # @yield [] the block that should be run in the threadpool, if `callable`
      #   isn't given
      #
      def defer(callable=nil, &block)
        @threadpool.defer(callable, &block)
      end
      
      # does a stat on '/', rescues all zookeeper-protocol exceptions
      #
      # @private intended for use in monitoring scripts
      # @return [bool]
      def ping?
        false unless connected?
        false|stat('/')
      rescue ZK::Exceptions::KeeperException
        false
      end

      # creates a new locker based on the name you send in
      #
      # @see ZK::Locker::ExclusiveLocker
      #
      # returns a ZK::Locker::ExclusiveLocker instance using this Client and provided
      # lock name
      #
      # ==== Arguments
      # * <tt>name</tt> name of the lock you wish to use
      #
      # ==== Examples
      #
      #   zk.locker("blah")
      #   # => #<ZK::Locker::ExclusiveLocker:0x102034cf8 ...>
      #
      def locker(name)
        Locker.exclusive_locker(self, name)
      end
      alias exclusive_locker locker

      # create a new shared locking instance based on the name given
      #
      # returns a ZK::Locker::SharedLocker instance using this Client and provided
      # lock name
      #
      # ==== Arguments
      # * <tt>name</tt> name of the lock you wish to use
      #
      # ==== Examples
      #
      #   zk.shared_locker("blah")
      #   # => #<ZK::Locker::SharedLocker:0x102034cf8 ...>
      #
      def shared_locker(name)
        Locker.shared_locker(self, name)
      end

      # Convenience method for acquiring a lock then executing a code block. This
      # will block the caller until the lock is acquired.
      #
      # ==== Arguments
      # * <tt>name</tt>: the name of the lock to use
      # * <tt>:mode</tt>: either :shared or :exclusive, defaults to :exclusive
      #
      # ==== Examples
      #
      #   zk.with_lock('foo') do
      #     # this code is executed while holding the lock
      #   end
      #
      def with_lock(name, opts={}, &b)
        mode = opts[:mode] || :exclusive

        raise ArgumentError, ":mode option must be either :shared or :exclusive, not #{mode.inspect}" unless [:shared, :exclusive].include?(mode)

        if mode == :shared
          shared_locker(name).with_lock(&b)
        else
          locker(name).with_lock(&b)
        end
      end

      # Convenience method for constructing a ZK::Election::Candidate object using this 
      # Client connection, the given election +name+ and +data+.
      #
      def election_candidate(name, data, opts={})
        opts = opts.merge(:data => data)
        ZK::Election::Candidate.new(self, name, opts)
      end

      # Convenience method for constructing a ZK::Election::Observer object using this 
      # Client connection, and the given election +name+.
      #
      def election_observer(name, opts={})
        ZK::Election::Observer.new(self, name, opts)
      end

      # creates a new message queue of name +name+
      #
      # returns a ZK::MessageQueue object
      #
      # ==== Arguments
      # * <tt>name</tt> the name of the queue
      #
      # ==== Examples
      #
      #   zk.queue("blah").publish({:some_data => "that is yaml serializable"})
      #
      def queue(name)
        MessageQueue.new(self, name)
      end

    end # Conveniences
  end   # Client
end     # ZK

