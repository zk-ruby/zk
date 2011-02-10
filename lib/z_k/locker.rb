module ZK
  # useful class for locking.
  # implements a locking algorithm talked about by Zookeeper documentation
  # @see http://hadoop.apache.org/zookeeper/docs/r3.0.0/recipes.html#sc_recipes_Locks Zookeeper docs
  class Locker < LockerBase

    # a blocking lock that waits until the lock is available for continuing
    # @param [Block] the block you want to execute once your client has
    #   received the lock
    # @example
    #   zk.locker("boooyah").with_lock do
    #     #some logic
    #   end
    def with_lock(&blk)
      create_lock_path!
      queue = Queue.new

      first_lock_blk = lambda do
        if have_first_lock?(true)
           queue << :locked
         end
      end

      @zk.watcher.register(root_lock_path, &first_lock_blk)
      first_lock_blk.call

      if queue.pop
        begin
          @locked = true
          return blk.call
        ensure
          unlock!
        end
      end
    end

    # a non-blocking lock
    # returns false if your client did not receive the lock
    # requires calling #unlock! if you *did* get the lock.
    # @see ZooKeeper::Locker#unlock!
    # @see ZooKeeper::Locker#with_lock
    # @example
    #   locker = zk.locker("booyah")
    #   locker.lock! # => true or false depending on if you got the lock or not
    #   locker.unlock!
    def lock!
      create_lock_path!
      if have_first_lock?(false)
        @locked = true
      else
        cleanup_lock_path!
        false
      end
    end

    # unlock the lock you have
    # @example
    #   locker = zk.locker("booyah")
    #   locker.lock!
    #   locker.unlock!
    def unlock!
      if @locked
        cleanup_lock_path!
        @locked = false
        true
      end
    end

    def locked?
      @locked
    end

  protected
    def have_first_lock?(watch = true)
      lock_files = @zk.children(root_lock_path, :watch => watch)
      lock_files.sort! {|a,b| digit_from_lock_path(a) <=> digit_from_lock_path(b)}
      digit_from_lock_path(lock_files.first) == digit_from_lock_path(@lock_path)
    end

    def digit_from_lock_path(path)
      path[/\d+$/].to_i
    end
  end
end
