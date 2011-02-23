module ZK
  # Implements locking primitives {described here}[http://hadoop.apache.org/zookeeper/docs/current/recipes.html#sc_recipes_Locks]
  #
  # There are both shared and exclusive lock implementations.
  #
  #
  # NOTE: These locks are _not_ safe for use across threads. If you want to use
  # the same Locker class between threads, it is your responsibility to
  # synchronize operations.
  #
  module Locker
    SHARED_LOCK_PREFIX  = 'sh'.freeze
    EXCLUSIVE_LOCK_PREFIX = 'ex'.freeze

    def self.shared_locker(zk, name)
      SharedLocker.new(zk, name)
    end

    def self.exclusive_locker(zk, name)
      ExclusiveLocker.new(zk, name)
    end
    
    class NoWriteLockFoundException < StandardError #:nodoc:
    end

    class WeAreTheLowestLockNumberException < StandardError #:nodoc:
    end

    class LockerBase
      include ZK::Logging

      attr_accessor :zk #:nodoc:

      # our absolute lock node path
      #
      # ex. '/_zklocking/foobar/__blah/lock000000007'
      attr_reader :lock_path #;nodoc:

      attr_reader :root_lock_path #:nodoc:

      def self.digit_from_lock_path(path) #:nodoc:
        path[/0*(\d+)$/, 1].to_i
      end

      def initialize(zookeeper_client, name, root_lock_node = "/_zklocking") 
        @zk = zookeeper_client
        @root_lock_node = root_lock_node
        @path = name
        @locked = false
        @waiting = false
        @root_lock_path = "#{@root_lock_node}/#{@path.gsub("/", "__")}"
      end
      
      # block caller until lock is aquired, then yield
      def with_lock
        lock!(true)
        yield
      ensure
        unlock!
      end

      # the basename of our lock path
      #
      # for the lock_path '/_zklocking/foobar/__blah/lock000000007'
      # lock_basename is 'lock000000007'
      #
      # returns nil if lock_path is not set
      def lock_basename
        lock_path and File.basename(lock_path)
      end

      def locked?
        false|@locked
      end
      
      def unlock!
        if @locked
          cleanup_lock_path!
          @locked = false
          true
        end
      end

      # returns true if this locker is waiting to acquire lock 
      def waiting? #:nodoc:
        false|@waiting
      end

      protected 
        def in_waiting_status
          w, @waiting = @waiting, true
          yield
        ensure
          @waiting = w
        end

        def digit_from(path)
          self.class.digit_from_lock_path(path)
        end

        def lock_children(watch=false)
          @zk.children(root_lock_path, :watch => watch)
        end

        def ordered_lock_children(watch=false)
          lock_children(watch).tap do |ary|
            ary.sort! { |a,b| digit_from(a) <=> digit_from(b) }
          end
        end

        def create_root_path!
          @zk.mkdir_p(@root_lock_path)
        end

        # prefix is the string that will appear in front of the sequence num,
        # defaults to 'lock'
        def create_lock_path!(prefix='lock')
          @lock_path = @zk.create("#{root_lock_path}/#{prefix}", "", :mode => :ephemeral_sequential)
          logger.debug { "got lock path #{@lock_path}" }
          @lock_path
        rescue Exceptions::NoNode
          create_root_path!
          retry
        end

        def cleanup_lock_path!
          logger.debug { "removing lock path #{@lock_path}" }
          @zk.delete(@lock_path)
          @zk.delete(root_lock_path) rescue Exceptions::NotEmpty
        end
    end

    class SharedLocker < LockerBase
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

      def lock_number #:nodoc:
        @lock_number ||= (lock_path and digit_from(lock_path))
      end

      # returns the sequence number of the next lowest write lock node
      #
      # raises NoWriteLockFoundException when there are no write nodes with a 
      # sequence less than ours
      #
      def next_lowest_write_lock_num #:nodoc:
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
      def next_lowest_write_lock_name #:nodoc:
        ary = ordered_lock_children()
        my_idx = ary.index(lock_basename)   # our idx would be 2

        not_found = lambda { raise NoWriteLockFoundException }

        ary[0..my_idx].reverse.find(not_found) { |n| n =~ /^#{EXCLUSIVE_LOCK_PREFIX}/ }
      end

      def got_read_lock? #:nodoc:
        false if next_lowest_write_lock_num 
      rescue NoWriteLockFoundException
        true
      end

      protected
        # TODO: make this generic, can either block or non-block
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
    class ExclusiveLocker < LockerBase
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
        def next_lowest_node
          ary = ordered_lock_children()
          my_idx = ary.index(lock_basename)

          raise WeAreTheLowestLockNumberException if my_idx == 0

          ary[(my_idx - 1)] 
        end

        def got_write_lock?
          ordered_lock_children.first == lock_basename
        end

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

