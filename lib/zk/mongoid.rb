module ZK
  module Mongoid
    # provides a lock_for_update method based on the current class name
    # and Mongoid document _id.
    #
    # Before use (in one of your Rails initializers, for example) you should
    # assign either a ZK::Client or ZK::Pool subclass to
    # ZK::Mongoid::Locking.zk_lock_pool.
    #
    # this class assumes the availability of a 'logger' method in the mixee
    #
    module Locking
      VALID_MODES = [:exclusive, :shared].freeze

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
          logger.debug { "we are locked for update, yield to the block" }
          yield
        else
          zk_with_lock(:mode => :exclusive, :name => name) { yield }
        end
      end
      alias :with_exclusive_lock :lock_for_update

      def with_shared_lock(name=nil)
        if locked_for_share?(name)
          yield
        else
          zk_with_lock(:mode => :shared, :name => name) { yield }
        end
      end

      # raises MustBeExclusivelyLockedException if we're not currently inside a
      # lock (optionally with +name+)
      def assert_locked_for_update!(name=nil)
        raise ZK::Exceptions::MustBeExclusivelyLockedException unless locked_for_update?(name)
      end

      # raises MustBeShareLockedException if we're not currently inside a shared lock
      # (optionally with +name+)
      def assert_locked_for_share!(name=nil)
        raise ZK::Exceptions::MustBeShareLockedException unless locked_for_share?(name)
      end

      def locked_for_update?(name=nil) #:nodoc:
        zk_mongoid_lock_registry[:exclusive].include?(zk_lock_name(name))
      end

      def locked_for_share?(name=nil) #:nodoc:
        zk_mongoid_lock_registry[:shared].include?(zk_lock_name(name))
      end

      def zk_lock_name(name=nil) #:nodoc:
        [self.class.to_s, self.id.to_s, name].compact.join('-')
      end

      protected
        def zk_mongoid_lock_registry
          Thread.current.zk_mongoid_lock_registry ||= { :shared => Set.new, :exclusive => Set.new }
        end

      private
        def zk_add_path_lock(opts={})
          mode, name = opts.values_at(:mode, :name)

          raise ArgumentError, "You must specify a :mode option" unless mode

          zk_assert_valid_mode!(mode)

          logger.debug { "adding #{zk_lock_name(name).inspect} to #{mode} lock registry" }

          self.zk_mongoid_lock_registry[mode] << zk_lock_name(name)
        end

        def zk_remove_path_lock(opts={})
          mode, name = opts.values_at(:mode, :name)

          raise ArgumentError, "You must specify a :mode option" unless mode

          zk_assert_valid_mode!(mode)

          logger.debug { "removing #{zk_lock_name(name).inspect} from #{mode} lock registry" }

          zk_mongoid_lock_registry[mode].delete(zk_lock_name(name))
        end

        def zk_with_lock(opts={})
          mode, name = opts.values_at(:mode, :name)

          zk_assert_valid_mode!(mode)

          zk_lock_pool.with_lock(zk_lock_name(name), :mode => mode) do
            zk_add_path_lock(opts)

            begin
              logger.debug { "acquired #{zk_lock_name(name).inspect}" }
              yield
            ensure
              logger.debug { "releasing #{zk_lock_name(name).inspect}" }
              zk_remove_path_lock(opts)
            end
          end
        end

        def zk_lock_pool
          @zk_lock_pool ||= ::ZK::Mongoid::Locking.zk_lock_pool
        end

        def zk_assert_valid_mode!(mode)
          raise ArgumentError, "#{mode.inspect} is not a valid mode value" unless VALID_MODES.include?(mode)
        end
    end
  end
end
