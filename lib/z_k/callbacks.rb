# some extensions to the ZookeeperCallbacks classes, mainly convenience
# interrogators
module ZK
  module Callbacks
    module CallbackClassExt
      # allows for easier construction of a user callback block that will be
      # called with the callback object itself as an argument
      #
      # example:
      #   
      #   WatcherCallback.new do |cb|
      #     puts "watcher callback called with argument: #{cb.inspect}"
      #   end
      #
      #   "watcher callback called with argument: #<ZookeeperCallbacks::WatcherCallback:0x1018a3958 @state=3, @type=1, ...>"
      #
      #
      def create(&block)
        # honestly, i have no idea how this could *possibly* work, but it does...
        cb_inst = new { block.call(cb_inst) }
      end
    end

    module WatcherCallbackExt
      include ZookeeperConstants

      def connecting?
        @state == ZOO_CONNECTING_STATE
      end

      def associating?
        @state == ZOO_ASSOCIATING_STATE
      end

      def connected?
        @state == ZOO_CONNECTED_STATE
      end

      def created?
        @type == ZOO_CREATED_EVENT
      end

      def deleted?
        @type == ZOO_DELETED_EVENT
      end

      def changed?
        @type == ZOO_CHANGED_EVENT
      end

      def child?
        @type == ZOO_CHILD_EVENT
      end

      def session?
        @type == ZOO_SESSION_EVENT
      end

      def not_watching?
        @type == ZOO_NOTWATCHING_EVENT
      end
    end

  end   # Callbacks
end     # ZK

ZookeeperCallbacks::Callback.extend(::ZK::Callbacks::CallbackClassExt)

ZookeeperCallbacks::WatcherCallback.send(:include, ::ZK::Callbacks::WatcherCallbackExt)


