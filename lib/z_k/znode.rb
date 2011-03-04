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

    # When a node is loaded, we apply a simple heuristic to determine if it's a
    # sequential node (as there's no way of knowing except based on the name) so if the 
    # basename of the node matches <tt>/\d{10}\Z/</tt>, we set sequential? to
    # true. ephemeral? is based off of the stat object.
    #
    class Base
      VALID_MODES = [:ephemeral, :persistent, :persistent_sequential, :ephemeral_sequential].freeze
      EPHEMERAL_MODES = [:ephemeral, :ephemeral_sequential].freeze

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
      attr_reader :stat #:nodoc:
      

      # Should be set to a ZK::Pool instance. this will be used by all instances of Base
      # to talk to zookeeper
      def self.zk_pool
        @zk_pool
      end

      def self.zk_pool=(zkp)
        @zk_pool = zkp
      end

      # create a new Znode object and immediately attempt to persist it. 
      #
      def self.create(*args, &block)
        new(*args, &block).tap do |node|
          node.save
        end
      end

      # throws a ZnodeNotSaved exception if the created node was not saved
      def self.create!(*args, &block)
        create(*args, &block).tap do |node|
          raise ZnodeNotSaved if node.new_record?
        end
      end

      # instantiates a Znode at path and calls #reload on it to load the data and current stat
      def self.load(*args)
        new(*args).reload
      end

      def initialize(path, opts={})
        @stat = @raw_data = nil

        @path       = path
        @new_record = true
        @destroyed  = false

        self.mode   = opts[:mode] || :persistent

        d = opts[:raw_data] and self.raw_data = d
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

      def ephemeral?
        EPHEMERAL_MODES.include?(@mode)
      end

      def reload(watch=false)
        self.raw_data, @stat = zk.get(path, :watch => watch)
        @new_record = false

        # only set mode if it was not set by user, as we're guessing a bit at
        # the 'sequential' aspect
        @mode ||= 
          if @stat.ephemeral_owner
            sequential_path? ? :ephemeral_sequential : :ephemeral
          else
            sequential_path? ? :persistent_sequential : :persistent
          end

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

        zk.children(path, opts).map do |base| 
          chld = self.class.new(zk, File.join(path, base))
          chld.reload if eager
          chld
        end
      end

      # Saves this node at path
      #
      # Raises ZnodeNotSaved if the save failed
      #
      def save!
        save or raise ZK::Exceptions::ZnodeNotSaved
      end

      # like save! but won't throw ZK::Exceptions::NodeExists, but instead will
      # return false
      def save
        create_or_update
        true
      rescue ZK::Exceptions::NodeExists, ZK::Exceptions::NoNode => e
        logger.debug { e.to_std_format }
        false
      rescue ZK::Exceptions::BadVersion => e
        raise ZK::Exceptions::StaleObjectError, e.message, caller
      end

      # creation mode for this object
      def mode=(v)
        raise ArgumentError, "#{v.inspect} is not a valid mode" unless VALID_MODES.include?(v) 

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
          @parent = self.class.load(dirname)
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

      def version #:nodoc:
        (@stat and @stat.version) or 0
      end

      # register a block to be called when a ZOO_CHANGED_EVENT is fired
      def on_changed
        register do |event|
          yield event if event.node_changed?
        end
      end

      # register a block to be called if the children of this node change
      def on_child
        register do |event|
          yield event if event.node_child?
        end
      end

      # register a block to be called if this node is deleted
      def on_deleted
        register do |event|
          yield event if event.node_deleted?
        end
      end

      # register a block to be called if this node is created
      def on_created
        register do |event|
          yield event if event.node_created?
        end
      end



      protected
        def sequential_path?
          false|(basename =~ /\d{10}\Z/)
        end

        def create_or_update
          zk.mkdir_p(dirname)
          new_record? ? create : update
          @new_record = false
        end

        def create
          # we set path here in case we're creating a sequential node
          @path = zk.create(path, raw_data, :mode => mode)
        end

        def update
          @stat = zk.set(path, raw_data, :version => version)
        end
        
        def zk
          self.class.zk_pool
        end
    end
  end
end


