module ZK
  module Client

    # This class forms the base API for interacting with ZooKeeper. Most people will
    # want to create instances of the class ZK::Client::Threaded, and the most
    # convenient way of doing that is through the top-level method `ZK.new`
    #
    # @note There is a lot of functionality mixed into the subclasses of this
    #   class! You should take a look at {Unixisms}, {Conveniences}, and
    #   {StateMixin} for a lot of the higher-level functionality!
    #
    # @example Create a new default connection
    #
    #   # if no host:port is given, we connect to localhost:2181 by default
    #   # (convenient for use in tests and in irb/pry)
    #
    #   zk = ZK.new
    #
    # @example Create a new connection, specifying host
    #
    #   zk = ZK.new('localhost:2181')
    #
    # @example For quick tasks, you can use the visitor pattern, (like the File class)
    #
    #   ZK.open('localhost:2181') do |zk|
    #     # do stuff with connection
    #   end
    #
    #   # connection is automatically closed
    #
    class Base
      # The Eventhandler is used by client code to register callbacks to handle
      # events triggerd for given paths. 
      #
      # @see ZK::Client::Base#register
      attr_reader :event_handler
      
      # @private the wrapped connection object
      attr_reader :cnx

      # @deprecated for backwards compatibility only
      # use ZK::Client::Base#event_handler instead
      def watcher
        event_handler
      end

      # returns true if the connection has been closed
      def closed?
        # XXX: should this be *our* idea of closed or ZOO_CLOSED_STATE ?
        defined?(::JRUBY_VERSION) ? jruby_closed? : mri_closed?
      end

      # @private
      def inspect
        "#<#{self.class.name}:#{object_id} zk_session_id=#{safe_session_id} ...>"
      end

      # Create a new client and connect to the zookeeper server. 
      #
      # @param [String] host should be a string of comma-separated host:port
      #   pairs. You can also supply an optional "chroot" suffix that will act as
      #   an implicit prefix to all paths supplied.
      #
      # @see ZK::Client::Threaded#initialize valid options to use with the
      #   synchronous (non-evented) client
      #
      # @example Threaded client with two hosts and a chroot path
      #    
      #   ZK::Client.new("zk01:2181,zk02:2181/chroot/path")
      #
      def initialize(host, opts={})
        # no-op
      end

      private
        # @private
        def jruby_closed?
          @cnx.state == Java::OrgApacheZookeeper::ZooKeeper::States::CLOSED
        end

        # @private
        def mri_closed?
          @cnx.closed?
        end

      public

      # reopen the underlying connection
      # returns state of connection after operation
      def reopen(timeout=nil)
        timeout ||= @session_timeout
        @cnx.reopen(timeout, @event_handler.get_default_watcher_block)
        @threadpool.start!  # restart the threadpool if previously stopped by close!
        state
      end

      # close the underlying connection and clear all pending events.
      def close!
        event_handler.clear!
        wrap_state_closed_error { @cnx.close unless @cnx.closed? }
      end

      # Create a node with the given path. The node data will be the given data.
      # The path is returned.
      # 
      # If the ephemeral option is given, the znode creaed will be removed by the
      # server automatically when the session associated with the creation of the
      # node expires. Note that ephemeral nodes cannot have children.
      # 
      # The sequence option, if true, will cause the server to create a sequential
      # node. The actual path name of a sequential node will be the given path
      # plus a suffix "_i" where i is the current sequential number of the node.
      # Once such a node is created, the sequential number for the path will be
      # incremented by one (i.e. the generated path will be unique across all
      # clients).
      # 
      # Note that since a different actual path is used for each invocation of
      # creating sequential node with the same path argument, the call will never
      # throw a NodeExists exception.
      # 
      # @todo clean up the verbiage around watchers
      #
      # This operation, if successful, will trigger all the watches left on the
      # node of the given path by exists and get API calls, and the watches left
      # on the parent node by children API calls.
      # 
      # If a node is created successfully, the ZooKeeper server will trigger the
      # watches on the path left by exists calls, and the watches on the parent
      # of the node by children calls.
      #
      # @param [String] path absolute path of the znode
      # @param [String] data the data to create the znode with
      # 
      # @option opts [Integer] :acl defaults to <tt>ZookeeperACLs::ZOO_OPEN_ACL_UNSAFE</tt>, 
      #   otherwise the ACL for the node. Should be a `ZOO_*` constant defined under the 
      #   ZookeeperACLs module in the zookeeper gem.
      #
      # @option opts [bool] :ephemeral (false) if true, the created node will be ephemeral
      #
      # @option opts [bool] :sequence (false) if true, the created node will be sequential
      #
      # @option opts [ZookeeperCallbacks::StringCallback] :callback (nil) provide a callback object
      #   that will be called when the znode has been created
      # 
      # @option opts [Object] :context (nil) an object passed to the `:callback`
      #   given as the `context` param
      #
      # @option opts [:ephemeral_sequential, :persistent_sequential, :persistent, :ephemeral] :mode (nil)
      #   may be specified instead of :ephemeral and :sequence options. If `:mode` *and* either of
      #   the `:ephermeral` or `:sequential` options are given, the `:mode` option will win
      #
      # @raise [ZK::Exceptions::NodeExists] if a node with the same `path` already exists
      # 
      # @raise [ZK::Exceptions::NoNode] if the parent node does not exist
      # 
      # @raise [ZK::Exceptions::NoChildrenForEphemerals] if the parent node of
      #   the given path is ephemeral
      #
      # @return [String] the path created on the server
      #
      # @todo Document the asynchronous methods
      #
      # @example create node, no data, persistent
      #
      #   zk.create("/path")
      #   # => "/path"
      #
      # @example create node, ACL will default to ACL::OPEN_ACL_UNSAFE
      #
      #   zk.create("/path", "foo")
      #   # => "/path"
      #
      # @example create ephemeral node
      #
      #   zk.create("/path", '', :mode => :ephemeral)
      #   # => "/path"
      #
      # @example create sequential node
      #
      #   zk.create("/path", '', :sequential => true)
      #   # => "/path0"
      #
      #   # or you can also do:
      #
      #   zk.create("/path", '', :mode => :persistent_sequence)
      #   # => "/path0"
      #
      #
      # @example create ephemeral and sequential node
      #
      #   zk.create("/path", '', :sequential => true, :ephemeral => true)
      #   # => "/path0"
      #
      #   # or you can also do:
      #
      #   zk.create("/path", "foo", :mode => :ephemeral_sequence)
      #   # => "/path0"
      #
      # @example create a child path
      #
      #   zk.create("/path/child", "bar")
      #   # => "/path/child"
      #
      # @example create a sequential child path
      #
      #   zk.create("/path/child", "bar", :sequential => true, :ephemeral => true)
      #   # => "/path/child0"
      #
      #   # or you can also do:
      #
      #   zk.create("/path/child", "bar", :mode => :ephemeral_sequence)
      #   # => "/path/child0"
      #
      # @hidden_example create asynchronously with callback object
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
      # @hidden_example create asynchronously with callback proc
      #
      #   callback = proc do |return_code, path, context, name|
      #       # do processing here
      #   end
      #
      #   context = Object.new
      #
      #   zk.create("/path", "foo", :callback => callback, :context => context)
      #
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

        rv = check_rc(@cnx.create(h), h)

        h[:callback] ? rv : rv[:path]
      end

      # Return the data and stat of the node of the given path.  
      # 
      # If `:watch` is true and the call is successful (no exception is
      # raised), registered watchers on the node will be 'armed'. The watch
      # will be triggered by a successful operation that sets data on the node,
      # or deletes the node. See `watcher` for documentation on how to register
      # blocks to be called when a watch event is fired.
      #
      # @todo fix references to Watcher documentation
      # 
      # Supports being executed asynchronousy by passing a callback object.
      # 
      # @param [String] path absolute path of the znode
      #
      # @option opts [bool] :watch (false) set to true if you want your registered
      #   callbacks for this node to be called on change
      #
      # @option opts [ZookeeperCallbacks::DataCallback] :callback to make this call asynchronously
      #
      # @option opts [Object] :context an object passed to the `:callback`
      #   given as the `context` param
      #
      # @return [Array] a two-element array of ['node data', #<ZookeeperStat::Stat>]
      #
      # @raise [ZK::Exceptions::NoNode] if no node with the given path exists.
      #
      # @example get data for path
      #
      #   zk.get("/path")
      #   # => ['this is the data', #<ZookeeperStat::Stat>]
      #   
      # @example get data and set watch on node
      #
      #   zk.get("/path", :watch => true)
      #   # => ['this is the data', #<ZookeeperStat::Stat>]
      #
      # @hidden_example get data asynchronously
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
      #
      def get(path, opts={})
        h = { :path => path }.merge(opts)

        setup_watcher!(:data, h)

        rv = check_rc(@cnx.get(h), h)

        opts[:callback] ? rv : rv.values_at(:data, :stat)
      end
  
      # Set the data for the node of the given path if such a node exists and the
      # given version matches the version of the node (if the given version is
      # -1, it matches any node's versions). Passing the version allows you to
      # perform optimistic locking, in that if someone changes the node's
      # data "behind your back", your update will fail. Since #create does not
      # return a ZookeeperStat::Stat object, you should be aware that nodes are
      # created with version == 0.
      # 
      # This operation, if successful, will trigger all the watches on the node
      # of the given path left by get calls.
      # 
      # @raise [ZK::Exceptions::NoNode] raised if no node with the given path exists 
      # 
      # @raise [ZK::Exceptions::BadVersion] raised if the given version does not
      #   match the node's version
      #
      # Called with a hash of arguments set.  Supports being executed
      # asynchronousy by passing a callback object.
      #
      # @param [String] path absolute path of the znode
      #
      # @param [String] data the data to be set on the znode. Note that setting
      #   the data to the exact same value currently on the node still increments
      #   the node's version and causes watches to be fired.
      # 
      # @option opts [Integer] :version (-1) matches all versions of a node if the
      #   default is used, otherwise acts as an assertion that the znode has the 
      #   supplied version.
      #   
      # @option opts [ZookeeperCallbacks::StatCallback] :callback will recieve the
      #   ZookeeperStat::Stat object asynchronously
      #
      # @option opts [Object] :context an object passed to the `:callback`
      #   given as the `context` param
      #
      # @example unconditionally set the data of "/path"
      #
      #   zk.set("/path", "foo")
      #
      # @example set the data of "/path" only if the version is 0
      #
      #   zk.set("/path", "foo", :version => 0)
      #
      def set(path, data, opts={})
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

        h = { :path => path, :data => data }.merge(opts)

        rv = check_rc(@cnx.set(h), h)

        opts[:callback] ? rv : rv[:stat]
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
      # @param [String] path absolute path of the znode
      #
      # @option opts [bool] :watch (false) set to true if you want to enable
      #   registered watches on this node
      # 
      # @option opts [ZookeeperCallbacks::StatCallback] :callback will recieve the
      #   ZookeeperStat::Stat object asynchronously
      #
      # @option opts [Object] :context an object passed to the `:callback`
      #   given as the `context` param
      #
      # @return [ZookeeperStat::Stat] a stat object of the specified node
      #
      # @example get stat for for path
      #   >> zk.stat("/path")
      #   # => ZK::Stat
      #
      # @example get stat for path and enable watchers
      #   >> zk.stat("/path", :watch => true)
      #   # => ZK::Stat
      #
      # @example exists for non existent path
      #
      #   >> stat = zk.stat("/non_existent_path")
      #   # => #<ZookeeperStat::Stat:0x000001eb54 @exists=false>
      #   >> stat.exists?
      #   # => false
      #
      #
      def stat(path, opts={})
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


        h = { :path => path }.merge(opts)

        setup_watcher!(:data, h)

        rv = @cnx.stat(h)

        return rv if opts[:callback] 

        case rv[:rc] 
        when Zookeeper::ZOK, Zookeeper::ZNONODE
          rv[:stat]
        else
          check_rc(rv, h) # throws the appropriate error
        end
      end


      # sugar around stat
      #
      # @example 
      #   
      #   # instead of:
      #
      #   zk.stat('/path').exists?
      #   # => true
      #
      #   # you can do:
      #
      #   zk.exists?('/path')
      #   # => true
      #
      # only works for the synchronous version of stat. for async version,
      # this method will act *exactly* like stat
      #
      def exists?(path, opts={})
        # XXX: this should use the underlying 'exists' call!
        rv = stat(path, opts)
        opts[:callback] ? rv : rv.exists?
      end

      # Return the list of the children of the node of the given path.
      # 
      # If the watch is true and the call is successful (no exception is thrown),
      # registered watchers of the children of the node will be enabled. The
      # watch will be triggered by a successful operation that deletes the node
      # of the given path or creates/delete a child under the node. See `watcher`
      # for documentation on how to register blocks to be called when a watch
      # event is fired.
      #
      # @note It is important to note that the list of children is _not sorted_. If you
      #   need them to be ordered, you must call `.sort` on the returned array
      # 
      # @raise [ZK::Exceptions::NoNode] if the node does not exist
      # 
      # @param [String] path absolute path of the znode
      #
      # @option opts [bool] :watch (false) set to true if you want your registered
      #   callbacks for this node to be called on change
      #
      # @option opts [ZookeeperCallbacks::StringsCallback] :callback to make this
      #   call asynchronously
      #
      # @option opts [Object] :context an object passed to the `:callback`
      #   given as the `context` param
      # 
      # @example get children for path
      #
      #   zk.create("/path", :data => "foo")
      #   zk.create("/path/child_0", :data => "child0")
      #   zk.create("/path/child_1", :data => "child1")
      #   zk.children("/path")
      #   # => ["child_0", "child_1"]
      #
      # @example get children and set watch
      #   
      #   # same setup as above
      #
      #   zk.children("/path", :watch => true)
      #   # => ["child_0", "child_1"]
      #
      def children(path, opts={})
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


        h = { :path => path }.merge(opts)

        setup_watcher!(:child, h)

        rv = check_rc(@cnx.get_children(h), h)
        opts[:callback] ? rv : rv[:children]
      end

      # Delete the node with the given path. The call will succeed if such a node
      # exists, and the given version matches the node's version (if the given
      # version is -1, it matches any node's versions), and the node has no children.
      # 
      # This operation, if successful, will trigger all the watches on the node
      # of the given path left by exists API calls, and the watches on the parent
      # node left by children API calls.
      #
      # Can be called with just the path, otherwise a hash with the arguments
      # set.  Supports being executed asynchronousy by passing a callback object.
      #
      # @raise [ZK::Exceptions::NoNode] raised if no node with the given path exists 
      # 
      # @raise [ZK::Exceptions::BadVersion] raised if the given version does not
      #   match the node's version
      #
      # @raise [ZK::Exceptions::NotEmpty] raised if the node has children
      # 
      # @param [String] path absolute path of the znode
      #
      # @option opts [Integer] :version (-1) matches all versions of a node if the
      #   default is used, otherwise acts as an assertion that the znode has the 
      #   supplied version.
      #
      # @option opts [ZookeeperCallbacks::VoidCallback] :callback will be called
      #   asynchronously when the operation is complete
      #
      # @option opts [Object] :context an object passed to the `:callback`
      #   given as the `context` param
      # 
      # @example delete a node
      #   zk.delete("/path")
      #
      # @example delete a node with a specific version
      #   zk.delete("/path", :version => 5)
      #
      def delete(path, opts={})
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


        h = { :path => path, :version => -1 }.merge(opts)
        rv = check_rc(@cnx.delete(h), h)
        opts[:callback] ? rv : nil
      end

      # Return the ACL and stat of the node of the given path.
      #
      # @todo this method is pretty much untested, YMMV
      # 
      # @raise [ZK::Exceptions::NoNode] if the parent node does not exist
      # 
      # @param [String] path absolute path of the znode
      #
      # @option opts [ZookeeperStat::Stat] (nil) provide a Stat object that will
      #   be set with the Stat information of the node path
      #
      # @option opts [ZookeeperCallback::AclCallback] (nil) :callback for an
      #   asynchronous call to occur
      #
      # @option opts [Object] :context (nil) an object passed to the `:callback`
      #   given as the `context` param
      # 
      # @example get acl
      #
      #   zk.get_acl("/path")
      #   # => [ACL]
      #
      # @example get acl with stat
      #
      #   stat = ZK::Stat.new
      #   zk.get_acl("/path", :stat => stat)
      #   # => [ACL]
      #
      def get_acl(path, opts={})
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

        h = { :path => path }.merge(opts)
        rv = check_rc(@cnx.get_acl(h), h)
        opts[:callback] ? rv : rv.values_at(:children, :stat)
      end

      # Set the ACL for the node of the given path if such a node exists and the
      # given version matches the version of the node. Return the stat of the
      # node.
      # 
      # @raise [ZK::Exceptions::NoNode] if the parent node does not exist
      #
      # @raise [ZK::Exceptions::BadVersion] raised if the given version does not
      #   match the node's version
      # 
      # @param [String] path absolute path of the znode
      #
      # @param [ZookeeperACLs] acls the acls to set on the znode
      # 
      # @option opts [Integer] :version (-1) matches all versions of a node if the
      #   default is used, otherwise acts as an assertion that the znode has the 
      #   supplied version.
      #
      # @option opts [ZookeeperCallbacks::VoidCallback] :callback will be called
      #   asynchronously when the operation is complete
      #
      # @option opts [Object] :context an object passed to the `:callback`
      #   given as the `context` param
      #
      # @todo: TBA - waiting on clarification of method use
      #
      def set_acl(path, acls, opts={})
        h = { :path => path, :acl => acls }.merge(opts)
        rv = check_rc(@cnx.set_acl(h), h)
        opts[:callback] ? rv : rv[:stat]
      end

      # @private
      # @todo need to document this a little more
      def set_debug_level(level)
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

      # returns the session_id of the underlying connection
      def session_id
        @cnx.session_id
      end

      # returns the session_passwd of the underlying connection
      def session_passwd
        @cnx.session_passwd
      end
      
      # Register a block that should be delivered events for a given path. After 
      # registering a block, you need to call {#get}, {#stat}, or {#children} with the
      # `:watch => true` option for the block to receive _the next event_ (see note).
      # {#get} and {#stat} will cause the block to receive events when the path is
      # created, deleted, or its data is changed. {#children} will cause the block to
      # receive events about its list of child nodes changing (i.e. being added
      # or deleted, but *not* their content changing).
      #
      # This method will return an {EventHandlerSubscription} instance that can be used
      # to remove the block from further updates by calling its `.unsubscribe` method.
      #
      # @note All node watchers are one-shot handlers. After an event is delivered to
      #   your handler, you *must* re-watch the node to receive more events. This
      #   leads to a pattern you will find throughout ZK code that avoids races,
      #   see the example below "avoiding a race"
      #
      # @example avoiding a race waiting for a node to be deleted
      #
      #   # we expect that '/path/to/node' exists currently and want to be notified
      #   # when it's deleted
      #
      #   # register a handler that will be called back when an event occurs on
      #   # node
      #   # 
      #   node_subscription = zk.register('/path/to/node') do |event|
      #     if event.node_deleted?
      #       do_something_when_node_deleted
      #     end
      #   end
      #
      #   # check to see if our condition is true *while* setting a watch on the node
      #   # if our condition happens to be true while setting the watch
      #   #
      #   unless exists?('/path/to/node', :watch => true)
      #     node_subscription.unsubscribe   # cancel the watch
      #     do_something_when_node_deleted  # call the callback
      #   end
      #
      #
      # @param [String] path the path you want to listen to
      #
      # @param [Block] block the block to execute when a watch event happpens
      #
      # @yield [event] We will call your block with the watch event object (which
      #   has the connection the event occurred on as its #zk attribute)
      #
      # @return [EventHandlerSubscription] the subscription object
      #   you can use to to unsubscribe from an event
      #
      # @see ZooKeeper::WatcherEvent
      # @see ZK::EventHandlerSubscription
      #
      def register(path, &block)
        event_handler.register(path, &block)
      end

      protected
        # @private
        def check_rc(hash, inputs=nil)
          code = hash[:rc]
          if code && (code != Zookeeper::ZOK)
            msg = inputs ? "inputs: #{inputs.inspect}" : nil
            raise Exceptions::KeeperException.by_code(code), msg 
          else
            hash
          end
        end

        # @private
        def setup_watcher!(watch_type, opts)
          event_handler.setup_watcher!(watch_type, opts)
        end

        # used in #inspect, doesn't raise an error if we're not connected
        def safe_session_id
          if cnx and cnx.session_id
            '0x%x' % cnx.session_id
          end
        rescue ZookeeperExceptions::ZookeeperException, ZK::Exceptions::KeeperException
          nil
        end
    end # Base
  end   # Client
end     # ZK

