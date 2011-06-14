module ZK
  module Client
    module Unixisms
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
      def mkdir_p(paths)
        Array(paths).flatten.map do |path|
          _mkdir_p_single(path)
        end
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

      def _mkdir_p_single(path)
        create(path, '', :mode => :persistent)
      rescue Exceptions::NodeExists
        return path
      rescue Exceptions::NoNode
        if File.dirname(path) == '/'
          # ok, we're screwed, blow up
          raise KeeperException, "could not create '/', something is wrong", caller
        end

        _mkdir_p_single(File.dirname(path))
        retry
      end

      # see ZK::Find for explanation
      def find(*paths, &block)
        ZK::Find.find(self, *paths, &block)
      end

      # will block the caller until +abs_node_path+ has been removed
      #
      # @private this method is of dubious value and may be removed in a later
      #   version
      #
      # @note this is dangerous to use in callbacks! there is only one
      #   event-delivery thread, so if you use this method in a callback or
      #   watcher, you *will* deadlock!
      def block_until_node_deleted(abs_node_path)
        queue = Queue.new
        ev_sub = nil

        node_deletion_cb = lambda do |event|
          if event.node_deleted?
            queue.enq(:deleted) 
          else
            queue.enq(:deleted) unless exists?(abs_node_path, :watch => true)
          end
        end

        ev_sub = watcher.register(abs_node_path, &node_deletion_cb)

        # set up the callback, but bail if we don't need to wait
        return true unless exists?(abs_node_path, :watch => true)  

        queue.pop # block waiting for node deletion
        true
      ensure
        # be sure we clean up after ourselves
        ev_sub.unregister if ev_sub
      end
    end
  end
end

