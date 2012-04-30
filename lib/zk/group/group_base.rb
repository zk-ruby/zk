module ZK
  module Group
    def self.new(*args)
      GroupBase.new(*args)
    end

    # The basis for forming different kinds of Groups with customizable
    # memberhip policies.
    class GroupBase
      extend Forwardable
      include Logging
      include Common

      def_delegators :@mutex, :synchronize
      protected :synchronize

      DEFAULT_ROOT = '/_zk/groups'

      # @private
      DEFAULT_PREFIX = 'm'.freeze

      # the ZK Client instance
      attr_reader :zk

      # the name for this group
      attr_reader :name

      # the absolute root path of this group, generally, this can be left at the default
      attr_reader :root

      # the combination of `"#{root}/#{name}"`
      attr_reader :path 

      # @return [ZK::Stat] the stat from the last time we either set or retrieved
      #   data from the server. 
      # @private
      attr_accessor :last_stat

      # Prefix used for creating sequential nodes under {#path} that represent membership.
      # The default is 'm', so for the path `/zkgroups/foo` a member path would look like
      # `/zkgroups/foo/m000000078`
      #
      # @return [String] the prefix 
      attr_accessor :prefix

      def initialize(zk, name, opts={})
        @orig_zk    = zk
        @zk         = GroupExceptionTranslator.new(zk, self)
        @name       = name.to_s
        @root       = opts.fetch(:root, DEFAULT_ROOT)
        @prefix     = opts.fetch(:prefix, DEFAULT_PREFIX)
        @path       = File.join(@root, @name)
        @mutex      = Monitor.new
        @created    = false

        @known_members = []
        @membership_subscriptions = []

        @membership_ev_sub = zk.register(path, :child) do |event|
          broadcast_membership_change!(event)
        end

        @on_connected_sub = zk.on_connected do |event|
          broadcast_membership_change!(event)
        end

        validate!
      end

      # stop receiving event notifications, tracking membership changes, etc.
      # XXX: what about memberships?
      def close
        synchronize do
          return unless @created
          @created = false

          @on_connected_sub.unsubscribe
          @membership_ev_sub.unsubscribe

          @known_members.clear
          @membership_subscriptions.each(&:unsubscribe)
        end
      end

      # this is "are we set up" not "did *we* create the group"
      def created?
        synchronize { !!@created }
      end

      # creates this group, does not raise an exception if the group already
      # exists.
      #
      # @return [String,nil] String containing the path of this group if
      #   created, nil if group already exists
      #
      # @overload create(}
      #   creates this group with empty data
      #
      # @overload create(data)
      #   creates this group with the given data. if the group already exists
      #   the data will not be written. 
      #
      #   @param [String] data the data to be set for this group
      #
      def create(*args)
        synchronize do
          begin
            create!(*args)
          rescue Exceptions::GroupAlreadyExistsError
            # ok, this is a little odd, if you call create! and it fails, semantically
            # in this method we're supposed to catch the exception and return. The problem
            # is that the @known_members and @last_stat won't have been set up. we want
            # both of these methods available, so we need to set that state up here, but
            # only if create! fails in this particular way
            set_initial_state!
            nil
          end
        end
      end

      # same as {#create} but raises an exception if the group already exists
      #
      # @raise [Exceptions::GroupAlreadyExistsError] if the group already exists
      def create!(*args)
        ensure_root_exists!

        data = args.empty? ? '' : args.first

        synchronize do
          zk.create(path, data).tap do
            logger.debug { "create!(#{path.inspect}, #{data.inspect}) succeeded, setting initial state" }
            set_initial_state!
          end
        end
      end

      # Creates a Member object that represents 'belonging' to this group.
      # 
      # The basic behavior is creating a unique path under the {#path} (using
      # a sequential, ephemeral node).
      #
      # You may receive notification that the member was created before this method
      # returns your Member instance. "heads up"
      #
      # @return [Member] used to control a single member of the group
      def join
        create_member(zk.create("#{path}/#{prefix}", :sequence => true, :ephemeral => true))
      end

      # returns the current list of member names, sorted.
      #
      # @option opts [true,false] :absolute (false) return member information
      #   as absolute znode paths.
      #
      # @option opts [true,false] :watch (true) causes a watch to be set on
      #   this group's znode for child changes. This will cause the on_membership_change
      #   callback to be triggered, when delivered.
      #
      def member_names(opts={})
        watch    = opts.fetch(:watch, true)
        absolute = opts.fetch(:absolute, false)

        zk.children(path, :watch => watch).sort.tap do |rval|
          rval.map! { |n| File.join(path, n) } if absolute
        end
      end

      # Register a block to be called back when the group membership changes. 
      #
      # Notifications will be delivered concurrently (i.e. using the client's
      # threadpool), but serially. In other words, when notification is
      # delivered to us that the group membership has changed, we queue up
      # notifications for all callbacks before handling the next event. This
      # way each callback will see the same sequence of updates every other
      # callback sees in order. They just may receive the notifications at
      # different times.
      #
      # XXX ^^ This is a lie ^^ XXX
      #
      # @note Due to the way ZooKeeper works, it's possible that you may not see every 
      #   change to the membership of the group. That is *very* important to know. 
      #   ZooKeeper _may batch updates_, so you can see a jump of members, especially
      #   if they're added very quickly. DO NOT assume you will receive a callback for _each
      #   individual membership added_.
      #
      # @options opts [true,false] :absolute (false) block will be called with members
      #   as absolute paths
      #
      # @yield [last_members,current_members] called when membership of the
      #   current group changes.
      #
      # @yieldparam [Array] last_members the last known membership list of the group
      #
      # @yieldparam [Array] current_members the list of members just retrieved from zookeeper
      #
      def on_membership_change(opts={}, &blk)
        MembershipSubscription.new(self, opts, blk).tap do |ms|
          # the watch is registered in create!
          synchronize { @membership_subscriptions << ms }
        end
      end

      # called by the MembershipSubscription object to deregister itself
      # @private
      def unregister(subscription)
        synchronize do
          @membership_subscriptions.delete(subscription)
        end
        nil
      end
      
      # @private
      def broadcast_membership_change!(_ignored)
        logger.debug { "#{__method__} received event #{_ignored.inspect}" }
        synchronize do

          # we might get an on_connected event before creation
          unless created?
            logger.debug { "uh, created? #{created?} so returning" }
            return
          end

          last_members, @known_members = @known_members, member_names(:watch => true)

          logger.debug { "last_members: #{last_members.inspect}" }
          logger.debug { "@known_members: #{@known_members.inspect}" }

          # we do this check so that on a connected event, we can run this callback
          # without producing false positives
          #
          if last_members == @known_members
            logger.debug { "membership data did not actually change, not notifying" }
          else
            @membership_subscriptions.each do |sub|
              lm, km = last_members.dup, @known_members.dup
              zk.defer { sub.notify(lm, km) }
            end
          end
        end
      end

      protected
        def set_initial_state!
          synchronize do
            logger.debug { "creating initial state!" }

            @created  = true
            @known_members = member_names

            logger.debug { "initial state set" }
          end
        end

        # Creates a Member instance for this Group. This its own method to allow
        # subclasses to override. By default, uses MemberBase
        def create_member(znode_path)
          logger.debug { "created member #{znode_path.inspect} returning object" }
          MemberBase.new(@orig_zk, self, znode_path)
        end

        def ensure_root_exists!
          zk.mkdir_p(root)
        end

        def validate!
          raise ArgumentError, "root must start with '/'" unless @root.start_with?('/')
        end
    end # GroupBase
  end # Group
end # ZK

