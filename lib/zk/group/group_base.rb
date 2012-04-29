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
        @zk         = GroupExceptionTranslator.new(zk)
        @name       = name.to_s
        @root       = opts.fetch(:root, DEFAULT_ROOT)
        @prefix     = opts.fetch(:prefix, DEFAULT_PREFIX)

        @last_stat = nil

        @path = File.join(@root, @name)

        validate!
      end

      # creates this group, does not raise an exception if the group already
      # exists.
      #
      # @return [String,nil] String containing the path of this group if
      #   created, nil if group already exists
      #
      # @overload create(opts={})
      #   creates this group with empty data
      #
      # @overload create(data, opts={})
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

        opts = args.extract_options!
        data = args.empty? ? '' : args.first

        zk.create(path, data, opts)
        @last_stat = Stat.create_blank
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

      # @return [Array[String]] a list of the members of this group as strings
      #
      # @option opts [true,false] :absolute (false) return member information
      #   as absolute znode paths.
      def member_names(opts={})
        zk.children(path).sort.tap do |rval|
          rval.map! { |n| File.join(path, n) } if opts[:absolute]
        end
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
    end # GroupBase
  end # Group
end # ZK

