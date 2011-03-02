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

      # the data containted at this node
      attr_accessor :data

      # what mode should this znode be created as? 
      # should be :persistent or :ephemeral
      #
      # for creating sequential nodes, you must use the class method Znode::Base.create(path, data, :mode => mode) 
      attr_reader :mode

      # the current stat object for the Znode at +path+
      # will be +nil+ if this node is new 
      attr_reader :stat

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
        @new_record = false
        @data, @stat = zk.get(path, :watch => watch)
        self
      end

      def delete
        zk.delete(path) if persisted?
        @destroyed = true
        freeze
      end

      def exists?(watch=false)
        zk.exists?(path, opts, :watch => watch)
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
      def on_change(&block)
        zk.register(path, &block)
      end

      protected
        def create_or_update
          new_record? ? create : update
        end

        def create
          zk.create(path, data, :mode => mode)
        end

        def update
          zk.set(path, data, :version => stat.version)
        end
    end
  end
end


