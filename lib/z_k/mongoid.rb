module ZK
  module Mongoid
    # provides a lock_for_update method based on the current class name
    # and Mongoid document _id.
    #
    # Before use (in one of your Rails initializers, for example) you should
    # assign either a ZK::Client or ZK::Pool subclass to
    # ZooKeeperLockMixin.zk_lock_pool.
    #
    # this class assumes the availability of a 'logger' method in the mixee
    #
    module Locking
      @@zk_lock_pool = nil unless defined?(@@zk_lock_pool)

      def self.zk_lock_pool
        @@zk_lock_pool
      end
      
      def self.zk_lock_pool=(pool)
        @@zk_lock_pool = pool 
      end


      # Provides a re-entrant zookeeper-based lock of a record.
      #
      # This also makes it possible to detect if the record has been locked before
      # performing a potentially dangerous operation by using the assert_locked_for_update!
      # instance method
      #
      # Locks are re-entrant per-thread, but will work as a mutex between
      # threads.
      #
      # You can optionally provide a 'name' which will act as a sub-lock of
      # sorts. For example, if you are going to create an embedded document,
      # and only want one process to be able to create it at a time (without
      # clobbering one another), but don't want to lock the entire record, you
      # can specify a name for the lock, that way the same code running
      # elsewhere will synchronize based on the parent record and the
      # particular action specified by +name+.
      #
      # ==== Example
      #
      # use of "name"
      #
      #   class Thing
      #     include Mongoid::Document
      #     include ZK::Mongoid::Locking
      #
      #     embedded_in :parent, :inverse_of => :thing
      #   end
      #
      #   class Parent
      #     include Mongoid::Document
      #     include ZK::Mongoid::Locking
      #
      #     embeds_one :thing
      #
      #     def lets_create_a_thing
      #       lock_for_update('thing_creation') do
      #         raise "We already got one! it's very nice!" if thing
      #
      #         do_something_that_might_take_a_while
      #         create_thing
      #       end
      #     end
      #   end
      #
      #
      # Now, while the creation of the Thing is synchronized, other processes
      # can update other aspects of Parent.
      #
      #
      def lock_for_update(name=nil)
        if locked_for_update?(name)
          yield
        else
          zk_with_lock(name) { yield }
        end
      end

      # raises MustBeExclusivelyLockedException if we're not currently inside a
      # lock (optionally with +name+)
      def assert_locked_for_update!(name=nil)
        raise MustBeExclusivelyLockedException unless locked_for_update?(name)
      end

      def locked_for_update?(name=nil) #:nodoc:
        zk_lock_registry.include?(zk_lock_name(name))
      end

      protected
        def zk_lock_registry
          Thread.current[:_zk_mongoid_lock_registry] ||= Set.new
        end

        def zk_add_path_lock(name=nil)
          logger.debug { "adding #{zk_lock_name(name).inspect} to lock registry" }
          self.zk_lock_registry << zk_lock_name(name)
        end

        def zk_remove_path_lock(name=nil)
          logger.debug { "removing #{zk_lock_name.inspect} from lock registry" }
          zk_lock_registry.delete(zk_lock_name(name))
        end

        def zk_lock_name(name=nil)
          @zk_lock_name ||= [self.class.to_s, self.id.to_s, name].compact.join('-')
        end

        def zk_with_lock(name=nil)
          zk_add_path_lock(name)
          zk_lock_pool.with_lock(zk_lock_name(name)) do
            logger.debug { "acquired #{zk_lock_name(name).inspect}" }
            yield
          end
        ensure
          logger.debug { "releasing #{zk_lock_name(name).inspect}" }
          zk_remove_path_lock(name)
        end

        def zk_lock_pool
          @zk_lock_pool ||= ::ZK::Mongoid::Locking.zk_lock_pool
        end
    end
  end
end
