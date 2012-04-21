module ZK
  module Client
    module Unixisms
      include ZookeeperConstants

      # Creates all parent paths and 'path' in zookeeper as persistent nodes with
      # zero data.
      #
      # ==== Arguments
      # * <tt>path</tt>: An absolute znode path to create
      #
      # ==== Examples
      #
      #   zk.exists?('/path')
      #   # => false
      # 
      #   zk.mkdir_p('/path/to/blah')
      #   # => "/path/to/blah"  
      #
      #--
      # TODO: write a non-recursive version of this. ruby doesn't have TCO, so
      # this could get expensive w/ psychotically long paths
      def mkdir_p(path)
        create(path, '', :mode => :persistent)
      rescue Exceptions::NodeExists
        return
      rescue Exceptions::NoNode
        if File.dirname(path) == '/'
          # ok, we're screwed, blow up
          raise Exceptions::NonExistentRootError, "could not create '/', are you chrooted into a non-existent path?", caller
        end

        mkdir_p(File.dirname(path))
        retry
      end

      # recursively remove all children of path then remove path itself
      def rm_rf(paths)
        Array(paths).flatten.each do |path|
          begin
            children(path).each do |child|
              rm_rf(File.join(path, child))
            end

            delete(path)
            nil
          rescue Exceptions::NoNode
          end
        end
      end

      # see ZK::Find for explanation
      def find(*paths, &block)
        ZK::Find.find(self, *paths, &block)
      end

      # will block the caller until `abs_node_path` has been removed
      #
      # @note this is dangerous to use in callbacks! there is only one
      #   event-delivery thread, so if you use this method in a callback or
      #   watcher, you *will* deadlock!
      #
      # @raise [ZK::Exceptions::InterruptedSession] If a session event occurs while we're
      #   blocked waiting for the node to be deleted, an exception that
      #   mixes in the InterruptedSession module will be raised. 
      #
      def block_until_node_deleted(abs_node_path)
        queue = Queue.new
        subs = []

        node_deletion_cb = lambda do |event|
          if event.node_deleted?
            queue.enq(:deleted) 
          else
            queue.enq(:deleted) unless exists?(abs_node_path, :watch => true)
          end
        end

        subs << event_handler.register(abs_node_path, &node_deletion_cb)

        # NOTE: this pattern may be necessary for other features with blocking semantics!

        session_cb = lambda do |event|
          queue.enq(event.state)
        end

        [:expired_session, :connecting, :closed].each do |sym|
          subs << event_handler.register_state_handler(sym, &session_cb)
        end
        
        # set up the callback, but bail if we don't need to wait
        return true unless exists?(abs_node_path, :watch => true)  

        case queue.pop
        when :deleted
          true
        when ZOO_EXPIRED_SESSION_STATE
          raise ZookeeperExceptions::ZookeeperException::SessionExpired
        when ZOO_CONNECTING_STATE
          raise ZookeeperExceptions::ZookeeperException::NotConnected
        when ZOO_CLOSED_STATE
          raise ZookeeperExceptions::ZookeeperException::ConnectionClosed
        else
          raise "Hit unexpected case in block_until_node_deleted"
        end
      ensure
        subs.each(&:unregister)
      end
    end
  end
end

