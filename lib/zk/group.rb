module ZK
  # A Group is a basic membership primitive. You pick a name
  # for the group, and then join, leave, and receive updates when
  # group membership changes. You can also get a list of other members of the
  # group.
  #
  module Group

    # The basis for forming different kinds of Groups with configurable
    # memberhip policies.
    class GroupBase
      include Logging

      DEFAULT_ROOT = '/zkgroups'

      # the ZK Client instance
      attr_reader :zk

      # the name for this group
      attr_reader :name

      # the absolute root path of this group, generally, this can be left at the default
      attr_reader :root

      # the combination of `"#{root}/#{name}"`
      attr_reader :path 

      # @return [ZookeeperStat::Stat] a 

      def initialize(zk, name, opts={})
        @zk   = zk
        @name = name.to_s
        @root = opts.fetch(:root, DEFAULT_ROOT)

        @version = nil

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
      #
      def create(*args)
        create!(*args)
      rescue Exceptions::GroupAlreadyExistsError
        nil
      end

      # same as {#create} but raises an exception if the group already exists
      def create!(*args)
        ensure_root_exists!

        translate_exceptions do
          opts = args.extract_options!
          data = args.empty? ? '' : args.first

          zk.create(path, data, opts)
        end
      end

      # Creates a Member object that represents 'belonging' to this group.
      # 
      # @abstract Subclass and implement according to the rules of 'joining' 
      #
      # @return [Member] used to control a single member of the group
      def join
        raise NotImplementedError, "implement in subclasses"
      end

      # @return [Array[Member]] A list of the members of this group as Member objects
      def members
      end

      # @return [Array[String]] a list of the members of this group as strings
      #   (with no path information)
      def member_names
        translate_exceptions do
          zk.children(path).sort
        end
      end

      # the data my znode contains
      def data
        translate_exceptions do
          rval, @last_stat = zk.get(path)
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
          @last_stat = zk.set(path, val)
          val
        end
      end

      protected
        def ensure_root_exists!
          zk.mkdir_p(root)
        end

        def translate_exceptions
          yield
        rescue Exceptions::NoNode
          raise Exceptions::GroupDoesNotExistError, "group at #{path} has not been created yet", caller
        rescue Exceptions::NodeExists
          raise Exceptions::GroupAlreadyExistsError, "group at #{path} already exists", caller
        end

        def validate!
          raise ArgumentError, "root must start with '/'" unless @root.start_with?('/')
        end
    end

    class Member
      attr_reader :zk 

      # @return [Group] the group instance this member belongs to
      attr_reader :group

      # @return [String] the relative path of this member under `group.path`
      attr_reader :name

      # @return [String] the absolute path of this member
      attr_reader :znode_path

      def initialize(zk, group, znode_path)
        @zk, @group, @znode_path = zk, group, znode_path
      end

      # Leave the group this membership is associated with.
      # In the basic implementation, this is not meant to kick another member
      # out of the group.
      def leave!
      end
    end
  end
end
