module ZK
  module Client
    # Convenience methods for creating instances of the cluster coordination
    # objects ZK provides, using the current connection.
    #
    # Mixed into {ZK::Client::Threaded}
    #
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
      # @private
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

      # Creates a new locker based on the name you provide, using this client
      # as the connection.
      #
      # @param name [String] the name of the lock you wish to use. see
      #   {ZK::Locker} for a description of how the name is used to generate a
      #   key.
      #
      # @return [Locker::ExclusiveLocker] instance using this Client and
      #   provided lock name. 
      #
      def locker(name)
        Locker.exclusive_locker(self, name)
      end
      alias exclusive_locker locker

      # create a new shared locking instance based on the name given
      #
      # @param name (see #locker)
      #
      # @return [Locker::SharedLocker] instance using this Client and provided
      #   lock name. 
      #
      def shared_locker(name)
        Locker.shared_locker(self, name)
      end

      # Convenience method for acquiring a lock then executing a code block. This
      # will block the caller until the lock is acquired, and release the lock
      # when the block is exited.
      #
      # Options are the same as for {Locker::LockerBase#lock #lock} with the addition of
      # `:mode`, documented below.
      #
      # @param name (see #locker)
      #
      # @option opts [:shared,:exclusive] :mode (:exclusive) the type of lock
      #   to create and then call with_lock on
      #
      # @return the return value of the given block
      #
      # @yield [lock] calls the block once the lock has been acquired with the
      #   lock instance
      #
      # @example
      #
      #   zk.with_lock('foo') do |lock|
      #     # this code is executed while holding the lock
      #   end
      #
      # @example with timeout
      #
      #   begin
      #     zk.with_lock('foo', :wait => 5.0) do |lock|
      #       # this code is executed while holding the lock
      #     end
      #   rescue ZK::Exceptions::LockWaitTimeoutError
      #     $stderr.puts "we didn't acquire the lock in time"
      #   end
      #
      # @raise [ArgumentError] if `opts[:mode]` is not one of the expected values
      #
      # @raise [ZK::Exceptions::LockWaitTimeoutError] if :wait timeout is
      #   exceeded without acquiring the lock
      #
      def with_lock(name, opts={}, &b)
        opts = opts.dup
        mode = opts.delete(:mode) { |_| :exclusive }

        raise ArgumentError, ":mode option must be either :shared or :exclusive, not #{mode.inspect}" unless [:shared, :exclusive].include?(mode)

        if mode == :shared
          shared_locker(name).with_lock(opts, &b)
        else
          locker(name).with_lock(opts, &b)
        end
      end

      # Constructs an {Election::Candidate} object using self as the connection
      #
      # @param [String] name the name of the election to participate in
      # @param [String] data the data we will write to the leadership node if/when we win
      #
      # @return [Election::Candidate] the candidate instance using self as a connection
      def election_candidate(name, data, opts={})
        opts = opts.merge(:data => data)
        ZK::Election::Candidate.new(self, name, opts)
      end

      # Constructs an {Election::Observer} object using self as the connection
      # 
      # @param name (see #election_candidate)
      #
      # @return [Election::Observer] the candidate instance using self as a connection
      def election_observer(name, opts={})
        ZK::Election::Observer.new(self, name, opts)
      end

      # creates a new message queue of name `name`
      # 
      # @note The message queue has some scalability limitations. For
      #   heavy-duty message processing, the author recommends investigating 
      #   a purpose-built solution.
      #
      # @return [MessageQueue] the new instance using self as its
      #   client
      #
      # @param [String] name the name of the queue
      #
      # @example
      #
      #   zk.queue("blah").publish({:some_data => "that is yaml serializable"})
      #
      def queue(name)
        MessageQueue.new(self, name)
      end

    end # Conveniences
  end   # Client
end     # ZK

