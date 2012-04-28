module ZK
  # A Group is a basic membership primitive. You pick a name
  # for the group, and then join, leave, and receive updates when
  # group membership changes. You can also get a list of other members of the
  # group.
  #
  module Group
    # common znode data access
    module Common
      # the data my znode contains
      def data
        translate_exceptions do
          rval, self.last_stat = zk.get(path)
          rval
        end
      end

      # Set the data in my group znode (the data at {#path})
      # 
      # In the base implementation, no version is given, this will just
      # overwrite whatever is currently there.
      #
      # @param [String] val the data to set
      # @return [String] the data that was set
      def data=(val)
        translate_exceptions do
          self.last_stat = zk.set(path, val)
          val
        end
      end

      protected
        # rescue underlying client exceptions and raise group-specific ones
        def translate_exceptions
          yield
        end
    end

    # A simple proxy for catching client errors and re-raising them as Group specific
    # errors (for clearer error reporting...we hope)
    #
    # @private
    class GroupExceptionTranslator
      def initialize(zk)
        @zk = zk
      end

      private
        def method_missing(m, *a, &b)
          super unless @zk.respond_to?(m)
          @zk.__send__(m, *a, &b)
        rescue Exceptions::NoNode
          raise Exceptions::GroupDoesNotExistError, "group at #{path} has not been created yet", caller
        rescue Exceptions::NodeExists
          raise Exceptions::GroupAlreadyExistsError, "group at #{path} already exists", caller
        end
    end

    # The basis for forming different kinds of Groups with customizable
    # memberhip policies.
    class GroupBase
      include Logging
      include Common

      DEFAULT_ROOT = '/zkgroups'

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
        zk.create("#{path}/#{prefix}")
      end

      # @return [Array[String]] a list of the members of this group as strings
      #   (with no path information)
      def member_names
        zk.children(path).sort
      end

      protected
        def ensure_root_exists!
          zk.mkdir_p(root)
        end

        def validate!
          raise ArgumentError, "root must start with '/'" unless @root.start_with?('/')
        end
    end # GroupBase
    
    class MemberBase
      include Common

      attr_reader :zk 

      # @return [Group] the group instance this member belongs to
      attr_reader :group

      # @return [String] the relative path of this member under `group.path`
      attr_reader :name

      # @return [String] the absolute path of this member
      attr_reader :znode_path

      def initialize(zk, group, znode_path)
        @zk = zk
        @group = group
        @znode_path = znode_path
      end

      # Leave the group this membership is associated with.
      # In the basic implementation, this is not meant to kick another member
      # out of the group.
      #
      # @abstract Implement 'leaving' behavior in subclasses
      def leave!
        raise NotImplementedError
      end
    end # MemberBase
  end
end
