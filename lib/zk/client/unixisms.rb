module ZK
  module Client
    module Unixisms
      include ZookeeperConstants

      # Creates all parent paths and 'path' in zookeeper as persistent nodes with
      # zero data.
      # 
      # @param [String] path An absolute znode path to create
      # 
      # @example
      #
      #   zk.exists?('/path')
      #   # => false
      # 
      #   zk.mkdir_p('/path/to/blah')
      #   # => "/path/to/blah"  
      #
      def mkdir_p(path)
        # TODO: write a non-recursive version of this. ruby doesn't have TCO, so
        # this could get expensive w/ psychotically long paths

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

      # Acts in a similar way to ruby's Find class. Performs a depth-first
      # traversal of every node under the given paths, and calls the given
      # block with each path found. Like the ruby Find class, you can call
      # {ZK::Find.prune} to avoid descending further into a given sub-tree
      #
      # @example list the paths under a given node
      #
      #   zk = ZK.new
      #   
      #   paths = %w[
      #     /root
      #     /root/alpha
      #     /root/bravo
      #     /root/charlie
      #     /root/charlie/rose
      #     /root/charlie/manson
      #     /root/charlie/manson/family
      #     /root/charlie/manson/murders
      #     /root/charlie/brown
      #     /root/delta
      #     /root/delta/blues
      #     /root/delta/force
      #     /root/delta/burke
      #   ]
      #   
      #   paths.each { |p| zk.create(p) }
      #   
      #   zk.find('/root') do |path|
      #     puts path
      #   
      #     ZK::Find.prune if path == '/root/charlie/manson'
      #   end
      #
      #   # this produces the output:
      #
      #   # /root
      #   # /root/alpha
      #   # /root/bravo
      #   # /root/charlie
      #   # /root/charlie/brown
      #   # /root/charlie/manson
      #   # /root/charlie/rose
      #   # /root/delta
      #   # /root/delta/blues
      #   # /root/delta/burke
      #   # /root/delta/force
      #
      # @param [Array[String]] paths a list of paths to recursively 
      #   yield the sub-paths of
      #
      # @see ZK::Find#find 
      def find(*paths, &block)
        ZK::Find.find(self, *paths, &block)
      end

      # Will _safely_ block the caller until `abs_node_path` has been removed.
      # This is trickier than it first appears. This method will wake the caller
      # if a session event occurs that would ensure the event would never be
      # delivered, and also checks to make sure that the caller is not calling
      # from the event distribution thread (which would cause a deadlock).
      #
      # @note this is dangerous to use in callbacks! there is only one
      #   event-delivery thread, so if you use this method in a callback or
      #   watcher, you *will* deadlock!
      #
      # @raise [Exceptions::InterruptedSession] If a session event occurs while we're
      #   blocked waiting for the node to be deleted, an exception that
      #   mixes in the InterruptedSession module will be raised. 
      #
      def block_until_node_deleted(abs_node_path)
        subs = []

        assert_we_are_not_on_the_event_dispatch_thread!

        raise ArgumentError, "argument must be String-ish, not: #{abs_node_path.inspect}" unless abs_node_path

        queue = Queue.new

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

