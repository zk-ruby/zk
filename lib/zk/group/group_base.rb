module ZK
  module Group
    # The basis for forming different kinds of Groups with customizable
    # memberhip policies.
    class GroupBase
      include Logging
      include Common

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

        @last_stat = nil
        @known_members = []

        @mutex = Monitor.new

        @path = File.join(@root, @name)

        validate!
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
        create!(*args)
      rescue Exceptions::GroupAlreadyExistsError
        nil
      end

      # same as {#create} but raises an exception if the group already exists
      def create!(*args)
        ensure_root_exists!

        data = args.empty? ? '' : args.first

        synchronize do
          zk.create(path, data).tap do
            @last_stat = Stat.create_blank
          end
        end
      end

      # Creates a Member object that represents 'belonging' to this group.
      # 
      # The basic behavior is creating a unique path under the {#path} (using
      # a sequential, ephemeral node).
      #
      # @return [Member] used to control a single member of the group
      def join
        create_member(zk.create("#{path}/#{prefix}", :sequence => true, :ephemeral => true))
      end

      # @return two lists of arrays, one is the last known list of members, the second
      #   is the current list of members
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

        rval = synchronize do 
          last_members, @known_members = @known_members, zk.children(path, :watch => watch).sort
          [last_members, @known_members.dup]
        end

        if absolute
          rval.each { |a| a.map! { |n| File.join(path, n) } }
        end

        rval
      end

      # Register a block to be called back when the group membership changes. 
      # In the case of a connection loss (recoverable, i.e. not
      # SESSION_EXPIRED), on reconnect your block will be called as if a child event
      # had occurred. This is because when we reconnect, we cannot be sure all
      # watches will be delivered, so to be safe we call.
      #
      #
      # @note Due to the way ZooKeeper works, it's possible that you may not see every 
      #   change to the membership of the group.
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
        opts = opts.dup
        opts.delete(:watch) # this would prevent the re-setting of the watch in member_names

        sub = zk.register(path, :child) do |event|
          
          blk.call(member_names(opts))
        end

        member_names(opts)

        sub
      end

      protected
        # Creates a Member instance for this Group. This its own method to allow
        # subclasses to override. By default, uses MemberBase
        def create_member(znode_path)
          MemberBase.new(@orig_zk, self, znode_path)
        end

        def ensure_root_exists!
          zk.mkdir_p(root)
        end

        def validate!
          raise ArgumentError, "root must start with '/'" unless @root.start_with?('/')
        end

        # delegates to the #synchronize method of a monitor we set up in the constructor
        # use to protect access to shared state like @last_stat and @known_members
        def synchronize
          @mutex.synchronize { yield }
        end
    end # GroupBase
  end # Group
end # ZK

