module ZK
  # Represents a single path in zookeeper, and can perform operations from the
  # perspective of that path. Operations performed through a Znode object will
  # return Znode instances where appropriate
  #
  # A Znode instance has a path, and will cache the last-known stat object and
  # node data.
  #
  # Znodes will do optimistic locking by default, and will throw a
  # ZK::Exceptions::BadVersion error if you attempt to update a node and its
  # been changed behind your back
  #
  module Znode
    class Base
      VALID_MODES = [:ephemeral, :persistent, :persistent_sequential, :ephemeral_sequential].freeze

      # this node's ZK::Client or ZK::Pool instance
      attr_reader :zk

      # the path of this znode
      attr_reader :path

      # the raw data as a string (possibly containing binary data) containted
      # at this node
      attr_accessor :raw_data

      # what mode should this znode be created as? 
      # should be :persistent or :ephemeral
      #
      # for creating sequential nodes, you must use the class method Znode::Base.create(path, data, :mode => mode) 
      attr_reader :mode

      # the current stat object for the Znode at +path+
      # will be +nil+ if this node is new 
      attr_reader :stat

      # create a new Znode object and immediately attempt to persist it. 
      #
      def self.create(zk, path, opts={})
        new(zk, path).tap do |node|
          node.raw_data = opts[:raw_data] || ''
          node.mode     = opts.delete(:mode) || :persistent
          node.save
        end
      end

      # instantiates a Znode at path and calls #reload on it to load the data and current stat
      def self.load(zk, path)
        new(zk, path).reload
      end

      def initialize(zk, path)
        @zk = zk
        @path = path
        @stat = @data = nil
        @new_record = true
        @destroyed = false
        @mode = :persistent
      end

      def new_record?
        @new_record
      end

      def destroyed?
        @destroyed
      end

      def persisted?
        !(new_record? || destroyed?)
      end

      def reload(watch=false)
        @raw_data, @stat = zk.get(path, :watch => watch)
        @new_record = false
        self
      end

      def delete
        zk.delete(path) if persisted?
        @destroyed = true
        freeze
      end

      def exists?(watch=false)
        zk.exists?(path, :watch => watch)
      end

      # returns the children of this node as Znode instances
      #
      # ==== Arguments
      # * <tt>:eager</tt>: eagerly load children, defaults to false. If true
      #   each child will have its +reload+ method called, otherwise only the 
      #   children will only have thier paths set.
      # * <tt>:watch</tt>: enables the watch for children of this node. 
      #
      def children(opts={})
        eager = opts.delete(:eager)

        ary = zk.children(path, opts)

        ary.map do |base| 
          chld = self.class.new(zk, File.join(path, base))
          chld.reload if eager
          chld
        end
      end

      # Saves this node at path. If the path already exists, will throw a 
      # ZK::Exceptions::NodeExists error
      #
      # If this is not a new_record? and there is a version mismatch, this
      # method will throw a ZK::Exception::BadVersion error.
      #
      def save!
        zk.mkdir_p(dirname)
        create_or_update
        @new_record = false
        nil
      end

      # like save! but won't throw ZK::Exceptions::NodeExists, but instead will
      # return false
      def save
        save!
      rescue ZK::Exceptions::NodeExists
        false
      end

      # creation mode for this object
      def mode=(v)
        @mode = v.to_sym
      end

      # the parent of this node, returns nil if path is '/'
      #
      # ==== Arguments
      # * +reload+: if true, reloads the parent object
      #
      def parent(reload=false)
        return nil if path == '/'

        if @parent
          @parent.reload if reload
        else
          @parent = self.class.load(zk, path)
        end
      end

      # the path-leading-up-to-this-node
      def dirname
        @dirname ||= File.dirname(path)
      end

      # the name of this node, without the path
      def basename
        @basename ||= File.basename(path)
      end

      # register a block to be called with a WatcherCallback event. a
      # convenience around registering an event handler. returns EventHandlerSubscription
      def register(&block)
        zk.register(path, &block)
      end

      # obtains an exclusive lock based on the path for this znode and yields to the block
      #
      # see ZK::Client#with_lock for valid options
      def with_lock(opts={})
        zk.with_lock(path, opts) { yield }
      end

      def inspect
        "#<#{self.class}:#{self.object_id} @path=#{path.inspect} ...>"
      end

      protected
        def create_or_update
          new_record? ? create : update
        end

        def create
          # we set path here in case we're creating a sequential node
          @path = zk.create(path, raw_data, :mode => mode)
        end

        def update
          @stat = zk.set(path, raw_data, :version => stat.version)
        end
    end
  end
end


