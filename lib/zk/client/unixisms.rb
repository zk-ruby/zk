module ZK
  module Client
    module Unixisms
      include Zookeeper::Constants
      include Exceptions

      # Creates all parent paths and 'path' in zookeeper as persistent nodes with
      # zero data.
      # 
      # @param [String] path An absolute znode path to create
      #
      # @option opts [String] :data ('') The data to place at path
      # 
      # @example
      #
      #   zk.exists?('/path')
      #   # => false
      # 
      #   zk.mkdir_p('/path/to/blah')
      #   # => "/path/to/blah"  
      #
      def mkdir_p(path, opts={})
        data = ''

        # if we haven't recursed, or we recursed and now we're back at the top
        if !opts.has_key?(:orig_path) or (path == opts[:orig_path])
          data = opts.fetch(:data, '')  # only put the data at the leaf node
        end

        create(path, data, :mode => :persistent)
      rescue NodeExists
        if !opts.has_key?(:orig_path) or (path == opts[:orig_path])  # we're at the leaf node
          set(path, data)
        end

        return
      rescue NoNode
        if File.dirname(path) == '/'
          # ok, we're screwed, blow up
          raise NonExistentRootError, "could not create '/', are you chrooted into a non-existent path?", caller
        end

        opts[:orig_path] ||= path

        mkdir_p(File.dirname(path), opts)
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
          rescue NoNode
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

      # Will _safely_ block the caller until `abs_node_path` has been removed
      # (this is trickier than it appears at first). This method will wake the
      # caller if a session event occurs that would ensure the event would
      # never be delivered. 
      #
      # @raise [Exceptions::InterruptedSession] If a session event occurs while we're
      #   blocked waiting for the node to be deleted, an exception that
      #   mixes in the InterruptedSession module will be raised, so for convenience,
      #   users can just rescue {InterruptedSession}.
      #
      # @raise [Zookeeper::Exceptions::SessionExpired] raised
      #   when we receive `ZOO_EXPIRED_SESSION_STATE` while blocking waiting for
      #   a deleted event. Includes the {InterruptedSession} module.
      #
      # @raise [Zookeeper::Exceptions::NotConnected] raised
      #   when we receive `ZOO_CONNECTING_STATE` while blocking waiting for
      #   a deleted event. Includes the {InterruptedSession} module.
      #
      # @raise [Zookeeper::Exceptions::ConnectionClosed] raised
      #   when we receive `ZOO_CLOSED_STATE` while blocking waiting for
      #   a deleted event. Includes the {InterruptedSession} module.
      #
      def block_until_node_deleted(abs_node_path)
        assert_we_are_not_on_the_event_dispatch_thread!

        raise ArgumentError, "argument must be String-ish, not: #{abs_node_path.inspect}" unless abs_node_path

        NodeDeletionWatcher.new(self, abs_node_path).block_until_deleted
      end
    end
  end
end

