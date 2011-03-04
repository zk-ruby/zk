module ZK
  # A ruby-friendly wrapper around the low-level zookeeper drivers. This is the
  # class that you will likely interact with the most. 
  #
  class Client
    extend Forwardable

    DEFAULT_TIMEOUT = 10

    attr_reader :event_handler

    attr_reader :cnx #:nodoc:

    # for backwards compatibility
    alias :watcher :event_handler #:nodoc:

    #:stopdoc:
    STATE_SYM_MAP = {
      Zookeeper::ZOO_CLOSED_STATE           => :closed,
      Zookeeper::ZOO_EXPIRED_SESSION_STATE  => :expired_session,
      Zookeeper::ZOO_AUTH_FAILED_STATE      => :auth_failed,
      Zookeeper::ZOO_CONNECTING_STATE       => :connecting,
      Zookeeper::ZOO_CONNECTED_STATE        => :connected,
      Zookeeper::ZOO_ASSOCIATING_STATE      => :associating,
    }.freeze
    #:startdoc:

    # Create a new client and connect to the zookeeper server. 
    #
    # +host+ should be a string of comma-separated host:port pairs. You can
    # also supply an optional "chroot" suffix that will act as an implicit 
    # prefix to all paths supplied.
    #
    # example:
    #   
    #   ZK::Client.new("zk01:2181,zk02:2181/chroot/path")
    #
    def initialize(host, opts={})
      @event_handler = EventHandler.new(self)
      @cnx = ::Zookeeper.new(host, DEFAULT_TIMEOUT, @event_handler.get_default_watcher_block)
      @threadpool = Threadpool.new
    end

    # Queue an operation to be run on an internal threadpool. You may either
    # provide an object that responds_to?(:call) or pass a block. There is no
    # mechanism for retrieving the result of the operation, it is purely
    # fire-and-forget, so the user is expected to make arrangements for this in
    # their code. 
    #
    # An ArgumentError will be raised if +callable+ does not <tt>respond_to?(:call)</tt>
    #
    # ==== Arguments
    # * <tt>callable</tt>: an object that <tt>respond_to?(:call)</tt>, takes precedence
    #   over a given block
    #
    def defer(callable=nil, &block)
      @threadpool.defer(callable, &block)
    end

    # returns true if the connection has been closed
    #--
    # XXX: should this be *our* idea of closed or ZOO_CLOSED_STATE ?
    def closed?
      defined?(::JRUBY_VERSION) ? jruby_closed? : mri_closed?
    end

    private
      def jruby_closed?
        @cnx.state == Java::OrgApacheZookeeper::ZooKeeper::States::CLOSED
      end

      def mri_closed?
        @cnx.state or false
      rescue RuntimeError => e
        # gah, lame error parsing here
        raise e if (e.message != 'zookeeper handle is closed') and not defined?(::JRUBY_VERSION)
        true
      end

    public

    # returns the current state of the connection as reported by the underlying driver
    # as a symbol. The possible values are <tt>[:closed, :expired_session, :auth_failed
    # :connecting, :connected, :associating]</tt>. 
    #
    # See the Zookeeper session 
    # {documentation}[http://hadoop.apache.org/zookeeper/docs/current/zookeeperProgrammers.html#ch_zkSessions]
    # for more information
    #
    def state
      if defined?(::JRUBY_VERSION) 
        @cnx.state.to_string.downcase.to_sym
      else
        STATE_SYM_MAP.fetch(@cnx.state) { |k| raise IndexError, "unrecognized state: #{k}" }
      end
    end

    # reopen the underlying connection
    # returns state of connection after operation
    def reopen(timeout=10, watcher=nil)
      @cnx.reopen(timeout, watcher)
      @threadpool.start!  # restart the threadpool if previously stopped by close!
      state
    end

    # Returns true if the underlying connection is in the +connected+ state.
    def connected?
      wrap_state_closed_error { @cnx.connected? }
    end

    # Returns true if the underlying connection is in the +associating+ state.
    def associating?
      wrap_state_closed_error { @cnx.associating? }
    end

    # Returns true if the underlying connection is in the +connecting+ state.
    def connecting?
      wrap_state_closed_error { @cnx.connecting? }
    end

    # Returns true if the underlying connection is in the +expired_session+ state.
    def expired_session?
      if defined?(::JRUBY_VERSION)
        @cnx.state == Java::OrgApacheZookeeper::ZooKeeper::States::EXPIRED_SESSION
      else
        wrap_state_closed_error { @cnx.state == Zookeeper::ZOO_EXPIRED_SESSION_STATE }
      end
    end


    # Create a node with the given path. The node data will be the given data,
    # and node acl will be the given acl.  The path is returned.
    # 
    # The ephemeral argument specifies whether the created node will be
    # ephemeral or not.
    # 
    # An ephemeral node will be removed by the server automatically when the
    # session associated with the creation of the node expires.
    # 
    # The sequence argument can also specify to create a sequential node. The
    # actual path name of a sequential node will be the given path plus a
    # suffix "_i" where i is the current sequential number of the node. Once
    # such a node is created, the sequential number will be incremented by one.
    # 
    # If a node with the same actual path already exists in the ZooKeeper, a
    # KeeperException with error code KeeperException::NodeExists will be
    # thrown. Note that since a different actual path is used for each
    # invocation of creating sequential node with the same path argument, the
    # call will never throw a NodeExists KeeperException.
    # 
    # If the parent node does not exist in the ZooKeeper, a KeeperException
    # with error code KeeperException::NoNode will be thrown.
    # 
    # An ephemeral node cannot have children. If the parent node of the given
    # path is ephemeral, a KeeperException with error code
    # KeeperException::NoChildrenForEphemerals will be thrown.
    # 
    # This operation, if successful, will trigger all the watches left on the
    # node of the given path by exists and get API calls, and the watches left
    # on the parent node by children API calls.
    # 
    # If a node is created successfully, the ZooKeeper server will trigger the
    # watches on the path left by exists calls, and the watches on the parent
    # of the node by children calls.
    #
    # Called with a hash of arguments set.  Supports being executed
    # asynchronousy by passing a callback object.
    # 
    # ==== Arguments
    # * <tt>path</tt> -- path of the node
    # * <tt>data</tt> -- initial data for the node, defaults to an empty string
    # * <tt>:acl</tt> -- defaults to <tt>ACL::OPEN_ACL_UNSAFE</tt>, otherwise the ACL for the node
    # * <tt>:ephemeral</tt> -- defaults to false, if set to true the created node will be ephemeral
    # * <tt>:sequence</tt> -- defaults to false, if set to true the created node will be sequential
    # * <tt>:callback</tt> -- provide a AsyncCallback::StringCallback object or
    #   Proc for an asynchronous call to occur
    # * <tt>:context</tt> --  context object passed into callback method
    # * <tt>:mode</tt> -- may be specified instead of :ephemeral and :sequence,
    #   accepted values are <tt>[:ephemeral_sequential, :persistent_sequential,
    #   :persistent, :ephemeral]</tt>
    # 
    # ==== Examples
    #
    # ===== create node, no data, persistent
    #
    #   zk.create("/path")
    #   # => "/path"
    #
    # ===== create node, ACL will default to ACL::OPEN_ACL_UNSAFE
    #
    #   zk.create("/path", "foo")
    #   # => "/path"
    #
    # ===== create ephemeral node
    #   zk.create("/path", :mode => :ephemeral)
    #   # => "/path"
    #
    # ===== create sequential node
    #   zk.create("/path", :mode => :persistent_sequence)
    #   # => "/path0"
    #
    # ===== create ephemeral and sequential node
    #   zk.create("/path", "foo", :mode => :ephemeral_sequence)
    #   # => "/path0"
    #
    # ===== create a child path
    #   zk.create("/path/child", "bar")
    #   # => "/path/child"
    #
    # ===== create a sequential child path
    #   zk.create("/path/child", "bar", :mode => :ephemeral_sequence)
    #   # => "/path/child0"
    #
    #--
    # TODO: document asynchronous callback
    #
    # ===== create asynchronously with callback object
    #
    #   class StringCallback
    #     def process_result(return_code, path, context, name)
    #       # do processing here
    #     end
    #   end
    #  
    #   callback = StringCallback.new
    #   context = Object.new
    #
    #   zk.create("/path", "foo", :callback => callback, :context => context)
    #
    # ===== create asynchronously with callback proc
    #
    #   callback = proc do |return_code, path, context, name|
    #       # do processing here
    #   end
    #
    #   context = Object.new
    #
    #   zk.create("/path", "foo", :callback => callback, :context => context)
    #
    #++
    def create(path, data='', opts={})
      h = { :path => path, :data => data, :ephemeral => false, :sequence => false }.merge(opts)

      if mode = h.delete(:mode)
        mode = mode.to_sym

        case mode
        when :ephemeral_sequential
          h[:ephemeral] = h[:sequence] = true
        when :persistent_sequential
          h[:ephemeral] = false
          h[:sequence] = true
        when :persistent
          h[:ephemeral] = false
        when :ephemeral
          h[:ephemeral] = true
        else
          raise ArgumentError, "Unknown mode: #{mode.inspect}"
        end
      end

      rv = check_rc(@cnx.create(h))

      h[:callback] ? rv : rv[:path]
    end

    # Return the data and stat of the node of the given path.  
    # 
    # If the watch is true and the call is successfull (no exception is
    # thrown), a watch will be left on the node with the given path. The watch
    # will be triggered by a successful operation that sets data on the node,
    # or deletes the node. See +watcher+ for documentation on how to register
    # blocks to be called when a watch event is fired.
    # 
    # A KeeperException with error code KeeperException::NoNode will be thrown
    # if no node with the given path exists.
    # 
    # Supports being executed asynchronousy by passing a callback object.
    # 
    # ==== Arguments
    # * <tt>path</tt> -- path of the node
    # * <tt>:watch</tt> -- defaults to false, set to true if you need to watch this node
    # * <tt>:callback</tt> -- provide a AsyncCallback::DataCallback object or
    #   Proc for an asynchronous call to occur
    # * <tt>:context</tt> --  context object passed into callback method
    # 
    # ==== Examples
    # ===== get data for path
    #   zk.get("/path")
    #   
    # ===== get data and set watch on node
    #   zk.get("/path", :watch => true)
    #
    #--
    # ===== get data asynchronously
    #
    #   class DataCallback
    #     def process_result(return_code, path, context, data, stat)
    #       # do processing here
    #     end
    #   end
    #
    #   zk.get("/path") do |return_code, path, context, data, stat|
    #     # do processing here
    #   end
    #  
    #   callback = DataCallback.new
    #   context = Object.new
    #   zk.get("/path", :callback => callback, :context => context)
    #++
    def get(path, opts={})
      h = { :path => path }.merge(opts)

      setup_watcher!(:data, h)

      rv = check_rc(@cnx.get(h))

      opts[:callback] ? rv : rv.values_at(:data, :stat)
    end
    
    # Set the data for the node of the given path if such a node exists and the
    # given version matches the version of the node (if the given version is
    # -1, it matches any node's versions). Return the stat of the node.
    # 
    # This operation, if successful, will trigger all the watches on the node
    # of the given path left by get_data calls.
    # 
    # A KeeperException with error code KeeperException::NoNode will be thrown
    # if no node with the given path exists. A KeeperException with error code
    # KeeperException::BadVersion will be thrown if the given version does not
    # match the node's version.  
    #
    # Called with a hash of arguments set.  Supports being executed
    # asynchronousy by passing a callback object.
    # 
    # ==== Arguments
    # * <tt>:path</tt> -- path of the node
    # * <tt>:data</tt> -- data to set
    # * <tt>:version</tt> -- defaults to -1, otherwise set to the expected matching version
    # * <tt>:callback</tt> -- provide a AsyncCallback::StatCallback object or
    #   Proc for an asynchronous call to occur
    # * <tt>:context</tt> --  context object passed into callback method
    # 
    # ==== Examples
    #   zk.set("/path", "foo")
    #   zk.set("/path", "foo", :version => 0)
    #
    #--
    # ===== set data asynchronously
    #
    #   class StatCallback
    #     def process_result(return_code, path, context, stat)
    #       # do processing here
    #     end
    #   end
    #  
    #   callback = StatCallback.new
    #   context = Object.new
    #
    #   zk.set("/path", "foo", :callback => callback, :context => context)
    #++
    def set(path, data, opts={})
      h = { :path => path, :data => data }.merge(opts)

      rv = check_rc(@cnx.set(h))

      opts[:callback] ? nil : rv[:stat]
    end

    # Return the stat of the node of the given path. Return nil if the node
    # doesn't exist.
    # 
    # If the watch is true and the call is successful (no exception is thrown),
    # a watch will be left on the node with the given path. The watch will be
    # triggered by a successful operation that creates/delete the node or sets
    # the data on the node.
    #
    # Can be called with just the path, otherwise a hash with the arguments
    # set. Supports being executed asynchronousy by passing a callback object.
    # 
    # ==== Arguments
    # * <tt>path</tt> -- path of the node
    # * <tt>:watch</tt> -- defaults to false, set to true if you need to watch
    #   this node
    # * <tt>:callback</tt> -- provide a AsyncCallback::StatCallback object or
    #   Proc for an asynchronous call to occur
    # * <tt>:context</tt> --  context object passed into callback method
    # 
    # ==== Examples
    # ===== exists for path
    #   zk.stat("/path")
    #   # => ZK::Stat
    #
    # ===== exists for path with watch set
    #   zk.stat("/path", :watch => true)
    #   # => ZK::Stat
    #
    # ===== exists for non existent path
    #   zk.stat("/non_existent_path")
    #   # => nil
    #
    #--
    # ===== exist node asynchronously
    #
    #   class StatCallback
    #     def process_result(return_code, path, context, stat)
    #       # do processing here
    #     end
    #   end
    #  
    #   callback = StatCallback.new
    #   context = Object.new
    #
    #   zk.exists?("/path", :callback => callback, :context => context)
    #++
    def stat(path, opts={})
      h = { :path => path }.merge(opts)

      setup_watcher!(:data, h)

      rv = @cnx.stat(h)

      return rv if opts[:callback] 

      case rv[:rc] 
      when Zookeeper::ZOK, Zookeeper::ZNONODE
        rv[:stat]
      else
        check_rc(rv) # throws the appropriate error
      end
    end

    # sugar around stat
    #
    # ===== instead of 
    #   zk.stat('/path').exists?
    #   # => true
    #
    # ===== you can do
    #   zk.exists?('/path')
    #   # => true
    #
    # this only works for the synchronous version of stat. for async version,
    # this method will act *exactly* like stat
    #
    def exists?(path, opts={})
      rv = stat(path, opts)
      opts[:callback] ? rv : rv.exists?
    end

    # closes the underlying connection and deregisters all callbacks
    def close!
      @event_handler.clear!
      wrap_state_closed_error { @cnx.close }
      @threadpool.shutdown
      nil
    end

    # Delete the node with the given path. The call will succeed if such a node
    # exists, and the given version matches the node's version (if the given
    # version is -1, it matches any node's versions).
    # 
    # A KeeperException with error code KeeperException::NoNode will be thrown
    # if the nodes does not exist.
    # 
    # A KeeperException with error code KeeperException::BadVersion will be
    # thrown if the given version does not match the node's version.
    # 
    # A KeeperException with error code KeeperException::NotEmpty will be
    # thrown if the node has children.
    # 
    # This operation, if successful, will trigger all the watches on the node
    # of the given path left by exists API calls, and the watches on the parent
    # node left by children API calls.
    #
    # Can be called with just the path, otherwise a hash with the arguments
    # set.  Supports being executed asynchronousy by passing a callback object.
    # 
    # ==== Arguments
    # * <tt>path</tt> -- path of the node to be deleted
    # * <tt>:version</tt> -- defaults to -1 (deletes any version), otherwise
    #   set to the expected matching version
    # * <tt>:callback</tt> -- provide a AsyncCallback::VoidCallback object or
    #   Proc for an asynchronous call to occur
    # * <tt>:context</tt> --  context object passed into callback method
    # 
    # ==== Examples
    #   zk.delete("/path")
    #   zk.delete("/path", :version => 0)
    #
    #--
    # ===== delete node asynchronously
    #
    #   class VoidCallback
    #     def process_result(return_code, path, context)
    #       # do processing here
    #     end
    #   end
    #  
    #   callback = VoidCallback.new
    #   context = Object.new
    #
    #   zk.delete(/path", :callback => callback, :context => context)
    #++
    def delete(path, opts={})
      h = { :path => path, :version => -1 }.merge(opts)
      rv = check_rc(@cnx.delete(h))
      nil
    end

    # Return the list of the children of the node of the given path.
    # 
    # If the watch is true and the call is successful (no exception is thrown),
    # a watch will be left on the node with the given path. The watch will be
    # triggered by a successful operation that deletes the node of the given
    # path or creates/delete a child under the node. See +watcher+ for
    # documentation on how to register blocks to be called when a watch event
    # is fired.
    # 
    # A KeeperException with error code KeeperException::NoNode will be thrown
    # if no node with the given path exists.
    # 
    # Can be called with just the path, otherwise a hash with the arguments
    # set.  Supports being executed asynchronousy by passing a callback object.
    # 
    # ==== Arguments
    # * <tt>path</tt> -- path of the node
    # * <tt>:watch</tt> -- defaults to false, set to true if you need to watch
    #   this node
    # * <tt>:callback</tt> -- provide a AsyncCallback::ChildrenCallback object
    #   or Proc for an asynchronous call to occur
    # * <tt>:context</tt> --  context object passed into callback method
    # 
    # ==== Examples
    # ===== get children for path
    #   zk.create("/path", :data => "foo")
    #   zk.create("/path/child", :data => "child1", :sequence => true)
    #   zk.create("/path/child", :data => "child2", :sequence => true)
    #   zk.children("/path")
    #   # => ["child0", "child1"]
    #
    # ====== get children and set watch
    #   zk.children("/path", :watch => true)
    #   # => ["child0", "child1"]
    #
    #--
    # ===== get children asynchronously
    #
    #   class ChildrenCallback
    #     def process_result(return_code, path, context, children)
    #       # do processing here
    #     end
    #   end
    #  
    #   callback = ChildrenCallback.new
    #   context = Object.new
    #   zk.children("/path", :callback => callback, :context => context)
    #++
    def children(path, opts={})
      h = { :path => path }.merge(opts)

      setup_watcher!(:child, h)

      rv = check_rc(@cnx.get_children(h))
      opts[:callback] ? nil : rv[:children]
    end

    # Return the ACL and stat of the node of the given path.
    # 
    # A KeeperException with error code KeeperException::Code::NoNode will be
    # thrown if no node with the given path exists.  
    #
    # Can be called with just the path, otherwise a hash with the arguments
    # set.  Supports being executed asynchronousy by passing a callback object.
    # 
    # ==== Arguments
    # * <tt>path</tt> -- path of the node
    # * <tt>:stat</tt> -- defaults to nil, provide a Stat object that will be
    #   set with the Stat information of the node path (TODO: test this)
    # * <tt>:callback</tt> -- provide a AsyncCallback::AclCallback object or
    #   Proc for an asynchronous call to occur
    # * <tt>:context</tt> --  context object passed into callback method
    # 
    # ==== Examples
    # ===== get acl
    #   zk.get_acl("/path")
    #   # => [ACL]
    #
    # ===== get acl with stat
    #   stat = ZK::Stat.new
    #   zk.get_acl("/path", :stat => stat)
    #
    #--
    # ===== get acl asynchronously
    #
    #   class AclCallback
    #     def processResult(return_code, path, context, acl, stat)
    #       # do processing here
    #     end
    #   end
    #  
    #   callback = AclCallback.new
    #   context = Object.new
    #   zk.acls("/path", :callback => callback, :context => context)
    #++
    def get_acl(path, opts={})
      h = { :path => path }.merge(opts)
      rv = check_rc(@cnx.get_acl(h))
      opts[:callback] ? nil : rv.values_at(:children, :stat)
    end

    # Set the ACL for the node of the given path if such a node exists and the
    # given version matches the version of the node. Return the stat of the
    # node.
    # 
    # A KeeperException with error code KeeperException::Code::NoNode will be
    # thrown if no node with the given path exists.
    # 
    # A KeeperException with error code KeeperException::Code::BadVersion will
    # be thrown if the given version does not match the node's version.
    #
    # Called with a hash of arguments set.  Supports being executed
    # asynchronousy by passing a callback object.
    # 
    # ==== Arguments
    # * <tt>path</tt> -- path of the node
    # * <tt>:acl</tt> -- acl to set
    # * <tt>:version</tt> -- defaults to -1, otherwise set to the expected matching version
    # * <tt>:callback</tt> -- provide a AsyncCallback::StatCallback object or
    #   Proc for an asynchronous call to occur
    # * <tt>:context</tt> --  context object passed into callback method
    # 
    # ==== Examples
    # TBA - waiting on clarification of method use
    #
    def set_acl(path, acls, opts={})
      h = { :path => path, :acl => acls }.merge(opts)
      rv = check_rc(@cnx.set_acl(h))
      opts[:callback] ? nil : rv[:stat]
    end

      

    #--
    #
    # EXTENSIONS
    #
    # convenience methods for dealing with zookeeper (rm -rf, mkdir -p, etc)
    #
    #++
    
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
        raise KeeperException, "could not create '/', something is wrong", caller
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

    # will block the caller until +abs_node_path+ has been removed
    #
    # NOTE: this is dangerous to use in callbacks! there is only one
    # event-delivery thread, so if you use this method in a callback or
    # watcher, you *will* deadlock!
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

    # creates a new locker based on the name you send in
    #
    # see ZK::Locker::ExclusiveLocker
    #
    # returns a ZK::Locker::ExclusiveLocker instance using this Client and provided
    # lock name
    #
    # ==== Arguments
    # * <tt>name</tt> name of the lock you wish to use
    #
    # ==== Examples
    #
    #   zk.locker("blah")
    #   # => #<ZK::Locker::ExclusiveLocker:0x102034cf8 ...>
    #
    def locker(name)
      Locker.exclusive_locker(self, name)
    end

    # create a new shared locking instance based on the name given
    #
    # returns a ZK::Locker::SharedLocker instance using this Client and provided
    # lock name
    #
    # ==== Arguments
    # * <tt>name</tt> name of the lock you wish to use
    #
    # ==== Examples
    #
    #   zk.shared_locker("blah")
    #   # => #<ZK::Locker::SharedLocker:0x102034cf8 ...>
    #
    def shared_locker(name)
      Locker.shared_locker(self, name)
    end

    # Convenience method for acquiring a lock then executing a code block. This
    # will block the caller until the lock is acquired.
    #
    # ==== Arguments
    # * <tt>name</tt>: the name of the lock to use
    # * <tt>:mode</tt>: either :shared or :exclusive, defaults to :exclusive
    #
    # ==== Examples
    #
    #   zk.with_lock('foo') do
    #     # this code is executed while holding the lock
    #   end
    #
    def with_lock(name, opts={}, &b)
      mode = opts[:mode] || :exclusive

      raise ArgumentError, ":mode option must be either :shared or :exclusive, not #{mode.inspect}" unless [:shared, :exclusive].include?(mode)

      if mode == :shared
        shared_locker(name).with_lock(&b)
      else
        locker(name).with_lock(&b)
      end
    end

    # Convenience method for constructing a ZK::Election::Candidate object using this 
    # Client connection, the given election +name+ and +data+.
    #
    def election_candidate(name, data, opts={})
      opts = opts.merge(:data => data)
      ZK::Election::Candidate.new(self, name, opts)
    end

    # Convenience method for constructing a ZK::Election::Observer object using this 
    # Client connection, and the given election +name+.
    #
    def election_observer(name, opts={})
      ZK::Election::Observer.new(self, name, opts)
    end

    # creates a new message queue of name +name+
    #
    # returns a ZK::MessageQueue object
    #
    # ==== Arguments
    # * <tt>name</tt> the name of the queue
    #
    # ==== Examples
    #
    #   zk.queue("blah").publish({:some_data => "that is yaml serializable"})
    #
    def queue(name)
      MessageQueue.new(self, name)
    end

    def set_debug_level(level) #:nodoc:
      if defined?(::JRUBY_VERSION)
        warn "set_debug_level is not implemented for JRuby" 
        return
      else
        num =
          case level
          when String, Symbol
            ZookeeperBase.const_get(:"ZOO_LOG_LEVEL_#{level.to_s.upcase}") rescue NameError
          when Integer
            level
          end

        raise ArgumentError, "#{level.inspect} is not a valid argument to set_debug_level" unless num

        @cnx.set_debug_level(num)
      end
    end

    # Register a block to be called on connection, when the client has
    # connected. The block will *always* be called asynchronously (on a
    # background thread).
    # 
    # the block will be called with no arguments
    #
    # returns an EventHandlerSubscription object that can be used to unregister
    # this block from further updates
    #
    def on_connected(&block)
      watcher.register_state_handler(:connected, &block).tap do
        defer { block.call } if connected?
      end
    end

    # register a block to be called when the client is attempting to reconnect
    # to the zookeeper server. the documentation says that this state should be
    # taken to mean that the application should enter into "safe mode" and operate
    # conservatively, as it won't be getting updates until it has reconnected
    #
    def on_connecting(&block)
      watcher.register_state_handler(:connecting, &block).tap do
        defer { block.call } if connecting?
      end
    end

    # register a block to be called when our session has expired. This usually happens
    # due to a network partitioning event, and means that all callbacks and watches must
    # be re-registered with the server
    #---
    # NOTE: need to come up with a way to test this
    def on_expired_session(&block)
      watcher.register_state_handler(:expired_session, &block).tap do
        defer { block.call } if expired_session?
      end
    end

    # registers a znode watcher on +path+ for events listed. see EventHandler#register
    # for details on what +events+ can be
    def on(path, *events, &block)
      watcher.register(path, :events => events, &block)
    end

    protected
      def wrap_state_closed_error
        yield
      rescue RuntimeError => e
        # gah, lame error parsing here
        raise e unless e.message == 'zookeeper handle is closed'
        false
      end

      def check_rc(hash)
        hash.tap do |h|
          if code = h[:rc]
            raise Exceptions::KeeperException.by_code(code) unless code == Zookeeper::ZOK
          end
        end
      end

      def setup_watcher!(watch_type, opts)
        @event_handler.setup_watcher!(watch_type, opts)
      end
  end
end

