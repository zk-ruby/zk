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
    # @example How to handle a fork()
    #
    #   zk = ZK.new
    #
    #   fork do
    #     zk.reopen() # <-- reopen is the important thing
    #
    #     zk.create('/child/pid', $$.to_s, :ephemeral => true)  # for example.
    #
    #     # etc.
    #   end
    #
    #
    class Base
      # The Eventhandler is used by client code to register callbacks to handle
      # events triggered for given paths. 
      # 
      # @see ZK::Client::Base#register
      attr_reader :event_handler
      
      # the wrapped connection object
      # @private 
      attr_reader :cnx
      private :cnx

      # maps from a symbol given as an option, to the numeric error constant that should
      # not raise an exception
      #
      # @private
      ERROR_IGNORE_MAP = {
        :no_node      => Zookeeper::ZNONODE,
        :node_exists  => Zookeeper::ZNODEEXISTS,
        :not_empty    => Zookeeper::ZNOTEMPTY,
        :bad_version  => Zookeeper::ZBADVERSION,
      }

      # @deprecated for backwards compatibility only
      # use ZK::Client::Base#event_handler instead
      def watcher
        event_handler
      end

      # returns true if the connection has been closed
      def closed?
        return true if cnx.nil?

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
      # @abstract Overridden in subclasses
      def initialize(host, opts={})
        # keep track of the process we were in when we started
        @host = host
        @pid  = Process.pid
      end

      private
        # @private
        def jruby_closed?
          cnx.state == Java::OrgApacheZookeeper::ZooKeeper::States::CLOSED
        end

        # @private
        def mri_closed?
          cnx.closed?
        end

      public

      # reopen the underlying connection
      #
      # The `timeout` param is here mainly for legacy support.
      #
      # @param [Numeric] timeout how long should we wait for
      #   the connection to reach a connected state before returning. Note that
      #   the method will not raise and will return whether the connection
      #   reaches the 'connected' state or not. The default is actually to use
      #   the same value that was passed to the constructor for 'timeout'
      #
      # @return [Symbol] state of connection after operation
      def reopen(timeout=nil)
      end

      # close the underlying connection and clear all pending events.
      #
      def close!
        event_handler.close
        close
      end

      # close the underlying connection, but do not reset callbacks registered
      # via the `register` method. This is to be used when preparing to fork.
      def close
        wrap_state_closed_error { cnx.close if cnx && !cnx.closed? }
      end

      # Connect to the server/cluster. This is called automatically by the
      # constructor by default. 
      def connect(opts={})
      end
       
      # this method will wait until the underlying connection is connected.
      # please note that when a connection is established, the underlying 
      # zookeeper gem performs this operation. you should only use this
      # method if you have received a connecting event and want to wait
      # until the connection has been re-established. 
      #
      # this method will block until you reach the connected? state or timeout
      # seconds have passed. if we enter another state, you will not be
      # awakened in the current implementation, so this method is somewhat
      # unsafe.
      #
      # use this with caution
      #
      # @private
      def wait_until_connected(timeout=10)
        cnx.wait_until_connected(timeout)
      end

      # Create a node with the given path. The node data will be the given data.
      # The path is returned.
      # 
      # If the ephemeral option is given, the znode created will be removed by the
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
      # If a node is created successfully, the ZooKeeper server will trigger the
      # watches on the path left by exists calls, and the watches on the parent
      # of the node by children calls.
      #
      # @overload create(path, opts={})
      #   creates a znode at the absolute `path` with blank data and given
      #   options
      #
      #   @option opts [Zookeeper::Callbacks::StringCallback] :callback (nil) provide a callback object
      #     that will be called when the znode has been created
      #   
      #   @option opts [Object] :context (nil) an object passed to the `:callback`
      #     given as the `context` param
      #
      #   @option opts [:set,nil] :or (nil) syntactic sugar to say 'if this
      #     path already exists, then set its contents.' Note that this will
      #     also create all intermediate paths as it delegates to
      #     {ZK::Client::Unixisms#mkdir_p}.  Note that this option can only be
      #     used to create or set persistent, non-sequential paths. If an
      #     option is used to specify either, an ArgumentError will be raised.
      #     (note: not available for zk-eventmachine)
      #
      #   @option opts [:ephemeral_sequential, :persistent_sequential, :persistent, :ephemeral] :mode (nil)
      #     may be specified instead of :ephemeral and :sequence options. If `:mode` *and* either of
      #     the `:ephermeral` or `:sequential` options are given, the `:mode` option will win
      #
      #   @option opts [:no_node,:node_exists] :ignore (nil) Do not raise an error if
      #     one of the given statuses is returned from ZooKeeper. This option
      #     may be given as either a symbol (for a single option) or as an Array
      #     of symbols for multiple ignores. This is useful when you want to
      #     create a node but don't care if it's already been created, and don't
      #     want to have to wrap it in a begin/rescue/end block.
      #
      #     * `:no_node`: silences the error case where you try to
      #       create `/foo/bar/baz` but any of the parent paths (`/foo` or
      #       `/foo/bar`) don't exist. 
      #
      #     * `:node_exists`: silences the error case where you try to create
      #       `/foo/bar` but it already exists.
      #
      # @overload create(path, data, opts={})
      #   creates a znode at the absolute `path` with given data and options
      # 
      #   @option opts [Zookeeper::Callbacks::StringCallback] :callback (nil) provide a callback object
      #     that will be called when the znode has been created
      #   
      #   @option opts [Object] :context (nil) an object passed to the `:callback`
      #     given as the `context` param
      #
      #   @option opts [:set,nil] :or (nil) syntactic sugar to say 'if this
      #     path already exists, then set its contents.' Note that this will
      #     also create all intermediate paths as it delegates to
      #     {ZK::Client::Unixisms#mkdir_p}.  Note that this option can only be
      #     used to create or set persistent, non-sequential paths. If an
      #     option is used to specify either, an ArgumentError will be raised.
      #     (note: not available for zk-eventmachine)
      #
      #   @option opts [:ephemeral_sequential, :persistent_sequential, :persistent, :ephemeral] :mode (nil)
      #     may be specified instead of :ephemeral and :sequence options. If `:mode` *and* either of
      #     the `:ephermeral` or `:sequential` options are given, the `:mode` option will win
      #
      #   @option opts [:no_node,:node_exists] :ignore (nil) Do not raise an error if
      #     one of the given statuses is returned from ZooKeeper. This option
      #     may be given as either a symbol (for a single option) or as an Array
      #     of symbols for multiple ignores. This is useful when you want to
      #     create a node but don't care if it's already been created, and don't
      #     want to have to wrap it in a begin/rescue/end block.
      #
      #     * `:no_node`: silences the error case where you try to
      #       create `/foo/bar/baz` but any of the parent paths (`/foo` or
      #       `/foo/bar`) don't exist. 
      #
      #     * `:node_exists`: silences the error case where you try to create
      #       `/foo/bar` but it already exists.
      #
      # @since 1.4.0: `:ignore` option
      #
      # @raise [ZK::Exceptions::NodeExists] if a node with the same `path` already exists
      # 
      # @raise [ZK::Exceptions::NoNode] if the parent node does not exist
      # 
      # @raise [ZK::Exceptions::NoChildrenForEphemerals] if the parent node of
      #   the given path is ephemeral
      #
      # @return [String] if created successfully the path created on the server
      #
      # @return [nil] if :ignore option is given and one of the errors listed 
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
      #   zk.create("/path", '', :mode => :persistent_sequential)
      #   # => "/path0"
      #
      # @example create ephemeral and sequential node
      #
      #   zk.create("/path", '', :sequence => true, :ephemeral => true)
      #   # => "/path0"
      #
      #   # or you can also do:
      #
      #   zk.create("/path", "foo", :mode => :ephemeral_sequential)
      #   # => "/path0"
      #
      # @example create a child path
      #
      #   zk.create("/path/child", "bar")
      #   # => "/path/child"
      #
      # @example create a sequential child path
      #
      #   zk.create("/path/child", "bar", :sequence => true, :ephemeral => true)
      #   # => "/path/child0"
      #
      #   # or you can also do:
      #
      #   zk.create("/path/child", "bar", :mode => :ephemeral_sequential)
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
      def create(path, *args)
        h = parse_create_args(path, *args)
        rv = call_and_check_rc(:create, h)
        h[:callback] ? rv : rv[:path]
      end

      # parses the arguments and returns a hash for passing to
      # call_and_check_rc. this is so subclasses can override easily
      def parse_create_args(path, *args)
        opts = args.extract_options!

        # be somewhat strict about how many arguments we accept.
        if args.length > 1
          raise ArgumentError, "create takes path, an optional data argument, and options, you passed: (#{path}, *#{args})"
        end

        # argh, terrible documentation bug, allow for :sequential, analagous to :sequence
        if opts.has_key?(:sequential)
          if opts.has_key?(:sequence)
            raise ArgumentError, "Only one of :sequential or :sequence options can be given, opts: #{opts}"
          end

          opts[:sequence] = opts.delete(:sequential)
        end

        data = args.first || ''

        rval = { :path => path, :data => data, :ephemeral => false, :sequence => false }.merge(opts)

        if mode = rval.delete(:mode)
          mode = mode.to_sym

          case mode
          when :ephemeral_sequential
            rval[:ephemeral] = rval[:sequence] = true
          when :persistent_sequential
            rval[:ephemeral] = false
            rval[:sequence] = true
          when :persistent
            rval[:ephemeral] = false
          when :ephemeral
            rval[:ephemeral] = true
          else
            raise ArgumentError, "Unknown mode: #{mode.inspect}"
          end
        end

        rval
      end
      private :parse_create_args

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
      # @option opts [Zookeeper::Callbacks::DataCallback] :callback to make this call asynchronously
      #
      # @option opts [Object] :context an object passed to the `:callback`
      #   given as the `context` param
      #
      # @return [Array] a two-element array of ['node data', #<Zookeeper::Stat>]
      #
      # @raise [ZK::Exceptions::NoNode] if no node with the given path exists.
      #
      # @example get data for path
      #
      #   zk.get("/path")
      #   # => ['this is the data', #<Zookeeper::Stat>]
      #   
      # @example get data and set watch on node
      #
      #   zk.get("/path", :watch => true)
      #   # => ['this is the data', #<Zookeeper::Stat>]
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

        rv = setup_watcher!(:data, h) do
          call_and_check_rc(:get, h)
        end

        opts[:callback] ? rv : rv.values_at(:data, :stat)
      end
  
      # Set the data for the node of the given path if such a node exists and the
      # given version matches the version of the node (if the given version is
      # -1, it matches any node's versions). Passing the version allows you to
      # perform optimistic locking, in that if someone changes the node's
      # data "behind your back", your update will fail. Since #create does not
      # return a Zookeeper::Stat object, you should be aware that nodes are
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
      # @option opts [Zookeeper::Callbacks::StatCallback] :callback will recieve the
      #   Zookeeper::Stat object asynchronously
      #
      # @option opts [Object] :context an object passed to the `:callback`
      #   given as the `context` param
      #
      # @option opts [:no_node,:bad_version] :ignore (nil) Do not raise an error if
      #   one of the given statuses is returned from ZooKeeper. This option
      #   may be given as either a symbol (for a single option) or as an Array
      #   of symbols for multiple ignores. This is useful when you want to
      #   set a node if it exists but don't care if it doesn't.
      #
      #   * `:no_node`: silences the error case where you try to
      #     set `/foo/bar/baz` but it doesn't exist.
      #
      #   * `:bad_version`: silences the error case where you give a `:version`
      #     but it doesn't match the server's version. 
      #
      # @since 1.4.0: `:ignore` option
      #
      # @return [Stat] the stat of the node after a successful update
      #
      # @return [nil] if `:ignore` is given and our update was not successful
      #
      # @example unconditionally set the data of "/path"
      #
      #   zk.set("/path", "foo")
      #
      # @example set the data of "/path" only if the version is 0
      #
      #   zk.set("/path", "foo", :version => 0)
      #
      # @example set the data of a non-existent node, check for success
      #   
      #   if zk.set("/path/does/not/exist", 'blah', :ignore => :no_node)
      #     puts 'the node existed and we updated it to say "blah"'
      #   else
      #     puts "pffft, i didn't wanna update that stupid node anyway"
      #   end
      #
      # @example fail to set the data of a node, ignore bad_version
      # 
      #   data, stat = zk.get('/path')
      #
      #   if zk.set("/path", 'blah', :version => stat.version, :ignore => :bad_version)
      #     puts 'the node existed, had the right version, and we updated it to say "blah"'
      #   else
      #     puts "guess someone beat us to it"
      #   end
      #
      # @hidden_example set data asynchronously
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
      #
      def set(path, data, opts={})
        h = { :path => path, :data => data }.merge(opts)

        rv = call_and_check_rc(:set, h)

        logger.debug { "rv: #{rv.inspect}" }

        # the reason we check the :rc here is: if the user set an :ignore which
        # has successfully squashed an error code from turning into an exception
        # we want to return nil. If the user was successful, we want to return
        # the Stat we got back from the server
        #
        # in the case of an async request, we want to return the result code of
        # the async operation (the submission)
        
        if opts[:callback]
          rv 
        elsif (rv[:rc] == Zookeeper::ZOK)
          rv[:stat]
        else
          nil
        end
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
      # @option opts [Zookeeper::Callbacks::StatCallback] :callback will recieve the
      #   Zookeeper::Stat object asynchronously
      #
      # @option opts [Object] :context an object passed to the `:callback`
      #   given as the `context` param
      #
      # @return [Zookeeper::Stat] a stat object of the specified node
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
      #   # => #<Zookeeper::Stat:0x000001eb54 @exists=false>
      #   >> stat.exists?
      #   # => false
      #
      #
      def stat(path, opts={})
        h = { :path => path }.merge(opts)

        setup_watcher!(:data, h) do
          rv = call_and_check_rc(:stat, h.merge(:ignore => :no_node))
          opts[:callback] ? rv : rv.fetch(:stat)
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
      # @hidden_option opts [Zookeeper::Callbacks::StringsCallback] :callback to make this
      #   call asynchronously
      #
      # @hidden_option opts [Object] :context an object passed to the `:callback`
      #   given as the `context` param
      #
      # @option opts [:no_node] :ignore (nil) Do not raise an error if
      #   one of the given statuses is returned from ZooKeeper. This option
      #   may be given as either a symbol (for a single option) or as an Array
      #   of symbols for multiple ignores. 
      #
      #   * `:no_node`: silences the error case where you try to
      #     set `/foo/bar/baz` but it doesn't exist.
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
      # @hidden_example
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
      #
      def children(path, opts={})

        h = { :path => path }.merge(opts)

        rv = setup_watcher!(:child, h) do
          call_and_check_rc(:get_children, h)
        end

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
      # @option opts [Zookeeper::Callbacks::VoidCallback] :callback will be called
      #   asynchronously when the operation is complete
      #
      # @option opts [Object] :context an object passed to the `:callback`
      #   given as the `context` param
      #
      # @option opts [:no_node,:not_empty,:bad_version] :ignore (nil) Do not
      #   raise an error if one of the given statuses is returned from ZooKeeper.
      #   This option may be given as either a symbol (for a single option) or as
      #   an Array of symbols for multiple ignores. This is useful when you want
      #   to delete a node but don't care if it's already been deleted, and don't
      #   want to have to wrap it in a begin/rescue/end block.
      #
      #   * `:no_node`: silences the error case where you try to
      #     delete `/foo/bar/baz` but it doesn't exist.
      #
      #   * `:not_empty`: silences the error case where you try to delete
      #     `/foo/bar` but it has children.
      #
      #   * `:bad_version`: silences the error case where you give a `:version`
      #     but it doesn't match the server's version. 
      #
      # @since 1.4.0: `:ignore` option
      # 
      # @example delete a node
      #   zk.delete("/path")
      #
      # @example delete a node with a specific version
      #   zk.delete("/path", :version => 5)
      #
      # @hidden_example
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
      #
      def delete(path, opts={})
        h = { :path => path, :version => -1 }.merge(opts)
        rv = call_and_check_rc(:delete, h)
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
      # @option opts [Zookeeper::Stat] (nil) provide a Stat object that will
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
      # @hidden_example
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
      #
      def get_acl(path, opts={})
        h = { :path => path }.merge(opts)
        rv = call_and_check_rc(:get_acl, h)
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
      # @param [Zookeeper::ACLs] acls the acls to set on the znode
      # 
      # @option opts [Integer] :version (-1) matches all versions of a node if the
      #   default is used, otherwise acts as an assertion that the znode has the 
      #   supplied version.
      #
      # @option opts [Zookeeper::Callbacks::VoidCallback] :callback will be called
      #   asynchronously when the operation is complete
      #
      # @option opts [Object] :context an object passed to the `:callback`
      #   given as the `context` param
      #
      # @todo: TBA - waiting on clarification of method use
      #
      def set_acl(path, acls, opts={})
        h = { :path => path, :acl => acls }.merge(opts)
        rv = call_and_check_rc(:set_acl, h)
        opts[:callback] ? rv : rv[:stat]
      end

      # Send authentication
      #
      # @param opts [String] :scheme authentication scheme being provided for.
      #
      # @param opts [String] :cert the authentication data.
      #
      # @example send digest authentication
      #
      #   zk.add_auth({ :scheme => 'digest', :cert => 'username:password' })
      #
      def add_auth(*args)
        opts = args.extract_options!
        call_and_check_rc(:add_auth, opts )
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
              begin
                ZookeeperBase.const_get(:"ZOO_LOG_LEVEL_#{level.to_s.upcase}")
              rescue NameError
                nil
              end
            when Integer
              level
            end

          raise ArgumentError, "#{level.inspect} is not a valid argument to set_debug_level" unless num

          cnx.set_debug_level(num)
        end
      end

      # @return [Fixnum] the session_id of the underlying connection
      def session_id
        cnx.session_id
      end

      # @return [String] the session_passwd of the underlying connection
      def session_passwd
        cnx.session_passwd
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
      # You can specify a list of event types after the path that you wish to
      # receive in your block using the `:only` option. This allows you to
      # register different blocks for different types of events. This sounds
      # more convenient, but __there is a potential pitfall__. The `:only`
      # option does filtering behind the scenes, so if you need a `:created`
      # event, but a `:changed` event is delivered instead, *and you don't have
      # a handler registered* for the `:changed` event which re-watches, then
      # you will most likely just miss it and blame the author. You should try
      # to stick to the style where you use a single block to test for the
      # different event types, re-registering as necessary. If you find that
      # block gets too out of hand, then use the `:only` option and break the
      # logic up between handlers.
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
      # @example only creation events
      #
      #   sub = zk.register('/path/to/znode', :only => :created) do |event|
      #     # do something when the node is created
      #   end
      #
      # @example only changed or children events
      #
      #   sub = zk.register('/path/to/znode', :only => [:changed, :child]) do |event|
      #     if event.node_changed?
      #       # do something on change
      #     else
      #       # we know it's a child event
      #     end
      #   end
      #
      # @example deprecated 1.0 style interests
      #
      #   sub = zk.register('/path/to/znode', [:changed, :child]) do |event|
      #     if event.node_changed?
      #       # do something on change
      #     else
      #       # we know it's a child event
      #     end
      #   end
      #
      # @param [String,:all] path the znode path you want to listen to, or the
      #   special value :all, that will cause the block to be delivered events
      #   for all znode paths
      # @param [Block] block the block to execute when a watch event happpens
      #
      # @yield [event] We will call your block with the watch event object (which
      #   has the connection the event occurred on as its #zk attribute)
      #
      # @return [EventHandlerSubscription] the subscription object
      #   you can use to to unsubscribe from an event
      #
      # @overload register(path, interests=nil, &block)
      #   @since 1.0
      #
      #   @deprecated use the `:only => :created` form
      #
      #   @param [Array,Symbol,nil] interests a symbol or array-of-symbols indicating
      #     which events you would like the block to be called for. Valid events
      #     are :created, :deleted, :changed, and :child. If nil, the block will
      #     receive all events
      #
      # @overload register(path, opts={}, &block)
      #   @since 1.1
      #
      #   @option opts [Array,Symbol,nil] :only (nil) a symbol or array-of-symbols indicating
      #     which events you would like the block to be called for. Valid events
      #     are :created, :deleted, :changed, and :child. If nil, the block will
      #     receive all events
      #
      # @see ZooKeeper::WatcherEvent
      # @see ZK::EventHandlerSubscription
      # @see https://github.com/slyphon/zk/wiki/Events the wiki page on using events effectively
      #
      def register(path, opts={}, &block)
        event_handler.register(path, opts, &block)
      end

      # returns true if the caller is calling from the event dispatch thread
      def event_dispatch_thread?
        cnx.event_dispatch_thread?
      end

      # @private
      def assert_we_are_not_on_the_event_dispatch_thread!(msg=nil)
        msg ||= "blocking method called on dispatch thread"
        raise Exceptions::EventDispatchThreadException, msg if event_dispatch_thread?
      end

      # called directly from the zookeeper event thread with every event, before they
      # get dispatched to the user callbacks. used by client implementations for
      # critical events like session_expired, so that we don't compete for
      # threads in the threadpool.
      #
      # @private
      def raw_event_handler(event)
      end

      private
        # does the current pid match the one that created us?
        def forked?
          Process.pid != @pid
        end

        def call_and_check_rc(meth, opts)
          # TODO: we should not be raising Zookeeper errors, that's not cool.
          raise Zookeeper::Exceptions::NotConnected if cnx.nil?

          scrubbed_opts = opts.dup
          scrubbed_opts.delete(:ignore)

          rv = cnx.__send__(meth, scrubbed_opts)

          check_rc(rv, opts)
        end

        # XXX: make this actually call the method on cnx
        def check_rc(rv_hash, inputs)
          code  = rv_hash[:rc]

          if code && (code != Zookeeper::ZOK)
            return rv_hash if ignore_set(inputs[:ignore]).include?(code)
            
            msg = inputs ? "inputs: #{inputs.inspect}" : nil
            raise Exceptions::KeeperException.by_code(code), msg 
          else
            rv_hash
          end
        end

        # arg is either a symbol (for one ignore) or an array
        # this method checks for validity, returns a set of the integers that
        # can be ignored or the empty set if arg is nil
        def ignore_set(arg)
          return Set.new if arg.nil?

          sym_array =
            case arg
            when Symbol
              [arg]
            when Array
              arg
            else
              raise ArgumentError, ":ignore option needs to be one of: #{ERROR_IGNORE_MAP.keys.inspect}, as a symbol or array of symbols, not #{arg.inspect}" 
            end

          bad_keys = sym_array - ERROR_IGNORE_MAP.keys

          unless bad_keys.empty?
            raise ArgumentError, "Sorry, #{bad_keys.inspect} not valid for :ignore, valid arguments are: #{ERROR_IGNORE_MAP.keys.inspect}"
          end

          Set.new(ERROR_IGNORE_MAP.values_at(*sym_array))
        end

        def setup_watcher!(watch_type, opts, &b)
          event_handler.setup_watcher!(watch_type, opts, &b)
        end

        # used in #inspect, doesn't raise an error if we're not connected
        def safe_session_id
          if cnx and cnx.session_id
            '0x%x' % cnx.session_id
          end
        rescue Zookeeper::Exceptions::ZookeeperException, ZK::Exceptions::KeeperException
          nil
        end
    end # Base
  end # Client
end # ZK

