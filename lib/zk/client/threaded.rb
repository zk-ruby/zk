module ZK
  module Client
    # This is the default client that ZK will use. In the zk-eventmachine gem,
    # there is an Evented client.
    #
    # If you want to register `on_*` callbacks (see {ZK::Client::StateMixin})
    # then you should pass a block, which will be called before the
    # connection is set up (this way you can get the `on_connected` event). See
    # the 'Register on_connected callback' example.
    #
    # A note on event delivery. There has been some confusion, caused by
    # incorrect documentation (which I'm very sorry about), about how many
    # threads are delivering events. The documentation for 0.9.0 was incorrect
    # in stating the number of threads used to deliver events. There was one,
    # unconfigurable, event dispatch thread. In 1.0 the number of event
    # delivery threads is configurable, but still defaults to 1. 
    #
    # If you use the threadpool/event callbacks to perform work, you may be
    # interested in registering an `on_exception` callback that will receive
    # all exceptions that occur on the threadpool that are not handled (i.e.
    # that bubble up to top of a block).
    #
    #
    # @example Register on_connected callback.
    #   
    #   # the nice thing about this pattern is that in the case of a call to #reopen
    #   # all your watches will be re-established
    #
    #   ZK::Client::Threaded.new('localhost:2181') do |zk|
    #     # do not do anything in here except register callbacks
    #     
    #     zk.on_connected do |event|
    #       zk.stat('/foo/bar', watch: true)
    #       zk.stat('/baz', watch: true)
    #     end
    #   end
    #
    class Threaded < Base
      include StateMixin
      include Unixisms
      include Conveniences
      include Logger

      DEFAULT_THREADPOOL_SIZE = 1

      # @private
      module Constants
        RUNNING   = :running
        PAUSED    = :paused
        CLOSE_REQ = :close_requested
        CLOSED    = :closed
      end
      include Constants

      # Construct a new threaded client.
      #
      # Pay close attention to the `:threaded` option, and have a look at the
      # [EventDeliveryModel](https://github.com/slyphon/zk/wiki/EventDeliveryModel)
      # page in the wiki for a discussion of the relative advantages and
      # disadvantages of the choices available. The default is safe, but the
      # alternative will likely provide better performance.
      #
      # @note The `:timeout` argument here is *not* the session_timeout for the
      #   connection. rather it is the amount of time we wait for the connection
      #   to be established. The session timeout exchanged with the server is 
      #   set to 10s by default in the C implemenation, and as of version 0.8.0 
      #   of slyphon-zookeeper has yet to be exposed as an option. That feature
      #   is planned. 
      #
      # @note The documentation for 0.9.0 was incorrect in stating the number
      #   of threads used to deliver events. There was one, unconfigurable,
      #   event dispatch thread. In 1.0 the number of event delivery threads is
      #   configurable, but still defaults to 1 and users are discouraged from
      #   adjusting the value due to the complexity this introduces. In 1.1
      #   there is a better option for achieving higher concurrency (see the
      #   `:thread` option)
      #
      #   The Management apologizes for any confusion this may have caused. 
      #
      # @since __1.1__: Instead of adjusting the threadpool, users are _strongly_ encouraged
      #   to use the `:thread => :per_callback` option to increase the
      #   parallelism of event delivery safely and sanely. Please see 
      #   [this wiki article](https://github.com/slyphon/zk/wiki/EventDeliveryModel) for more
      #   information and a demonstration.
      #
      # @param host (see Base#initialize)
      #
      # @option opts [true,false] :reconnect (true) if true, we will register
      #   the equivalent of `on_session_expired { zk.reopen }` so that in the
      #   case of an expired session, we will keep trying to reestablish the
      #   connection. You *almost definately* want to leave this at the default.
      #   The only reason not to is if you already have a handler registered 
      #   that does something application specific, and you want to avoid a 
      #   conflict.
      #
      # @option opts [Fixnum] :retry_duration (nil) for how long (in seconds)
      #   should we wait to re-attempt a synchronous operation after we receive a
      #   ZK::Exceptions::Retryable error. This exception (or really, group of
      #   exceptions) is raised when there has been an unintentional network
      #   connection or session loss, so retrying an operation in this situation
      #   is like saying "If we are disconnected, How long should we wait for the
      #   connection to become available before attempthing this operation?"
      #
      #   The default `nil` means automatic retry is not attempted.
      #
      #   This is a global option, and will be used for all operations on this
      #   connection, however it can be overridden for any individual operation.
      #
      # @option opts [:single,:per_callback] :thread (:single) choose your event
      #   delivery model:
      #
      #   * `:single`: There is one thread, and only one callback is called at
      #     a time. This is the default mode (for now), and will provide the most
      #     safety for your app. All events will be delivered as received, to
      #     callbacks in the order they were registered. This safety has the
      #     tradeoff that if one of your callbacks performs some action that blocks
      #     the delivery thread, you will not recieve other events until it returns.
      #     You're also limiting the concurrency of your app. This should be fine
      #     for most simple apps, and is a good choice to start with when
      #     developing your application
      #
      #   * `:per_callback`: This option will use a new-style Actor model (inspired by 
      #     [Celluloid](https://github.com/celluloid/celluloid)) that uses a
      #     per-callback queue and thread to allow for greater concurrency in
      #     your app, whille still maintaining some kind of sanity. By choosing
      #     this option your callbacks will receive events in order, and will
      #     receive only one at a time, but in parallel with other callbacks.
      #     This model has the advantage you can have all of your callbacks
      #     making progress in parallel, and if one of them happens to block,
      #     it will not affect the others.
      #    
      #   * see {https://github.com/slyphon/zk/wiki/EventDeliveryModel the wiki} for a
      #     discussion and demonstration of the effect of this setting.
      #
      # @option opts [Fixnum] :timeout used as a default for calls to {#reopen}
      #   and {#connect} (including the initial default immediate connection)
      #
      # @option opts [true,false] :connect (true) Immediately connect to the
      #   server. It may be useful to pass false if you wish to do callback
      #   setup without passing a block. You must then call {#connect} 
      #   explicitly.
      #
      # @yield [self] calls the block with the new instance after the event
      #   handler and threadpool have been set up, but before any connections
      #   have been made.  This allows the client to register watchers for
      #   session events like `connected`. You *cannot* perform any other
      #   operations with the client as you will get a NoMethodError (the
      #   underlying connection is nil).
      #
      # @return [Threaded] a new client instance
      #
      # @see Base#initialize
      def initialize(host, opts={}, &b)
        super(host, opts)

        tp_size = opts.fetch(:threadpool_size, DEFAULT_THREADPOOL_SIZE)
        @threadpool = Threadpool.new(tp_size)

        @connection_timeout = opts[:timeout] || DEFAULT_TIMEOUT # maybe move this into superclass?
        @event_handler   = EventHandler.new(self, opts)

        @reconnect = opts.fetch(:reconnect, true)

        setup_locks

        @client_state = RUNNING # this is to distinguish between *our* state and the underlying connection state

        # this is the last status update we've received from the underlying connection
        @last_cnx_state = nil

        @retry_duration = opts.fetch(:retry_duration, nil).to_i

        yield self if block_given?

        @fork_subs = [
          ForkHook.prepare_for_fork(method(:pause_before_fork_in_parent)),
          ForkHook.after_fork_in_parent(method(:resume_after_fork_in_parent)),
          ForkHook.after_fork_in_child(method(:reopen)),
        ]

        ObjectSpace.define_finalizer(self, self.class.finalizer(@fork_subs))

        connect(opts) if opts.fetch(:connect, true)
      end
      
      # ensure that the initializer and the reopen code set up the mutexes
      # the same way (i.e. use a Monitor or a Mutex, no, really, I screwed 
      # this up once) 
      def setup_locks
        @mutex = Monitor.new
        @cond = @mutex.new_cond
      end
      private :setup_locks

      # @private
      def self.finalizer(hooks)
        proc { hooks.each(&:unregister) }
      end

      # @option opts [Fixnum] :timeout how long we will wait for the connection
      #   to be established. If timeout is nil, we will wait forever: *use
      #   carefully*.
      def connect(opts={})
        @mutex.synchronize { unlocked_connect(opts) }
      end

      # (see Base#reopen)
      def reopen(timeout=nil)
        # Clear outstanding watch restrictions
        @event_handler.clear_outstanding_watch_restrictions!

        # If we've forked, then we can call all sorts of normally dangerous 
        # stuff because we're the only thread. 
        if forked?
          # ok, just to sanity check here
          raise "[BUG] we hit the fork-reopening code in JRuby!!" if defined?(::JRUBY_VERSION)

          logger.debug { "reopening everything, fork detected!" }

          setup_locks

          @pid           = Process.pid
          @client_state  = RUNNING                     # reset state to running if we were paused

          old_cnx, @cnx = @cnx, nil
          old_cnx.close! if old_cnx # && !old_cnx.closed?

          join_and_clear_reconnect_thread

          @mutex.synchronize do
            # it's important that we're holding the lock, as access to 'cnx' is
            # synchronized, and we want to avoid a race where event handlers
            # might see a nil connection. I've seen this exception occur *once*
            # so it's pretty rare (it was on 1.8.7 too), but just to be double
            # extra paranoid

            @event_handler.reopen_after_fork!
            @threadpool.reopen_after_fork!          # prune dead threadpool threads after a fork()

            unlocked_connect
          end
        else
          @mutex.synchronize do
            if @client_state == PAUSED
              # XXX: what to do in this case? does it matter?
            end

            logger.debug { "reopening, no fork detected" }
            @last_cnx_state = Zookeeper::ZOO_CONNECTING_STATE
            
            @client_state  = RUNNING # reset state to running if we were paused or closed

            timeout ||= @connection_timeout     # or @connection_timeout here is the docuemnted behavior on Base#reopen

            @cnx.reopen(timeout)                # ok, we werent' forked, so just reopen

            # this is a bit of a hack, because we need to wait until the event thread
            # delivers the connected event, which we used to be able to rely on just the
            # connection doing. since we don't want to call the @cnx.state method to check
            # (rather use the cached @last_cnx_state), we wait for consistency's sake
            wait_until_connected_or_dying(timeout)
          end
        end

        state
      end

      # Before forking, call this method to peform a "stop the world" operation on all
      # objects associated with this connection. This means that this client will spin down
      # and join all threads (so make sure none of your callbacks will block forever), 
      # and will tke no action to keep the session alive. With the default settings,
      # if a ping is not received within 20 seconds, the session is considered dead
      # and must be re-established so be sure to call {#resume_after_fork_in_parent}
      # before that deadline, or you will have to re-establish your session.
      #
      # @raise [InvalidStateError] when called and not in running? state
      # @private
      def pause_before_fork_in_parent
        @mutex.synchronize do
          raise InvalidStateError, "client must be running? when you call #{__method__}" unless (@client_state == RUNNING)
          @client_state = PAUSED
      
          logger.debug { "#{self.class}##{__method__}" }

          @cond.broadcast
        end

        join_and_clear_reconnect_thread

        # the compact is here because the @cnx *may* be nil when this callback is fired by the
        # ForkHook (in the case of ZK.open). The race is between the GC calling the finalizer
        [@event_handler, @threadpool, @cnx].compact.each(&:pause_before_fork_in_parent)
      ensure
        logger.debug { "##{__method__} returning" }
      end

      # @private
      def resume_after_fork_in_parent
        @mutex.synchronize do
          raise InvalidStateError, "client must be paused? when you call #{__method__}" unless (@client_state == PAUSED)
          @client_state = RUNNING

          logger.debug { "##{__method__}" }

          if @cnx
            @cnx.resume_after_fork_in_parent
            spawn_reconnect_thread
          end

          [@event_handler, @threadpool].compact.each(&:resume_after_fork_in_parent)

          @cond.broadcast
        end
      end

      # (see Base#close!)
      #
      # @note We will make our best effort to do the right thing if you call
      #   this method while in the threadpool. It is _a much better idea_ to
      #   call us from the main thread, or _at least_ a thread we're not going
      #   to be trying to shut down as part of closing the connection and
      #   threadpool.
      #
      def close!
        @mutex.synchronize do 
          return if [:closed, :close_requested].include?(@client_state)
          logger.debug { "moving to :close_requested state" }
          @client_state = CLOSE_REQ
          @cond.broadcast
        end

        join_and_clear_reconnect_thread

        on_tpool = on_threadpool?

        # Ok, so the threadpool will wait up to N seconds while joining each thread.
        # If _we're on a threadpool thread_, have it wait until we're ready to jump
        # out of this method, and tell it to wait up to 5 seconds to let us get
        # clear, then do the rest of the shutdown of the connection 
        #
        # if the user *doesn't* hate us, then we just join the shutdown_thread immediately
        # and wait for it to exit
        #
        shutdown_thread = Thread.new do
          Thread.current[:name] = 'shutdown'
          @threadpool.shutdown(10)

          # this will call #close
          super

          @mutex.synchronize do
            logger.debug { "moving to :closed state" }
            @client_state = CLOSED
            @last_cnx_state = nil
            @cond.broadcast
          end
        end

        on_tpool ? shutdown_thread : shutdown_thread.join(30)
      end

      # this overrides the implementation in StateMixin
      def connected?
        @mutex.synchronize { running? && @last_cnx_state == Zookeeper::ZOO_CONNECTED_STATE }
      end

      def associating?
        @mutex.synchronize { running? && @last_cnx_state == Zookeeper::ZOO_ASSOCIATING_STATE }
      end

      def connecting?
        @mutex.synchronize { running? && @last_cnx_state == Zookeeper::ZOO_CONNECTING_STATE }
      end

      def expired_session?
        @mutex.synchronize do
          return false unless @cnx and running?

          if defined?(::JRUBY_VERSION)
            !@cnx.state.alive?
          else
            @last_cnx_state == Zookeeper::ZOO_EXPIRED_SESSION_STATE
          end
        end
      end

      def state
        @mutex.synchronize do
          STATE_SYM_MAP.fetch(@last_cnx_state) { |k| raise IndexError, "unrecognized state: #{k.inspect}" }
        end
      end

      # {see ZK::Client::Base#close}
      def close
        super
        subs, @fork_subs = @fork_subs, []
        subs.each(&:unsubscribe)
        nil
      end

      # (see Threadpool#on_threadpool?)
      def on_threadpool?
        @threadpool and @threadpool.on_threadpool?
      end

      # (see Threadpool#on_exception)
      def on_exception(&blk)
        @threadpool.on_exception(&blk)
      end

      def closed?
        return true if @mutex.synchronize { @client_state == CLOSED }
        super
      end

      # this is where the :on option is implemented for {Base#create}
      def create(path, *args)
        opts = args.extract_options!

        or_opt = opts.delete(:or)
        args << opts

        if or_opt
          hash = parse_create_args(path, *args)
 
          raise ArgumentError, "valid options for :or are nil or :set, not #{or_opt.inspect}" unless or_opt == :set 
          raise ArgumentError, "you cannot create an ephemeral node when using the :or option" if hash[:ephemeral]
          raise ArgumentError, "you cannot create an sequence node when using the :or option"  if hash[:sequence]
         
          mkdir_p(path, :data => hash[:data])
          path
        else
          # ok, none of our business, hand it up to mangement
          super(path, *args)
        end
      end

      # @private
      def raw_event_handler(event)
        return unless event.session_event?
        
        @mutex.synchronize do
          @last_cnx_state = event.state

          @cond.broadcast # wake anyone waiting for a connection state update
        end
      rescue Exception => e
        logger.error { "BUG: Exception caught in raw_event_handler: #{e.to_std_format}" } 
      end

      # @private
      def wait_until_connected_or_dying(timeout)
        time_to_stop = timeout ? Time.now + timeout : nil

        @mutex.synchronize do
          while true
            if timeout
              now = Time.now
              break if (@last_cnx_state == Zookeeper::ZOO_CONNECTED_STATE) || (now > time_to_stop) || (@client_state != RUNNING)
              deadline = time_to_stop.to_f - now.to_f
              @cond.wait(deadline)
            else
              break if (@last_cnx_state == Zookeeper::ZOO_CONNECTED_STATE) || (@client_state != RUNNING)
              @cond.wait
            end
          end
        end

        logger.debug { "#{__method__} @last_cnx_state: #{@last_cnx_state.inspect}, time_left? #{timeout ? (Time.now.to_f < time_to_stop.to_f) : 'true'}, @client_state: #{@client_state.inspect}" }
      end

      # @private
      def wait_until_closed(timeout=nil)
        time_to_stop = timeout ? Time.now + timeout : nil

        @mutex.synchronize do
          while true
            if timeout
              now = Time.now
              break if (now > time_to_stop) || (@client_state == CLOSED)
              deadline = time_to_stop.to_f - now.to_f
              @cond.wait(deadline)
            else
              break if @client_state == CLOSED
              @cond.wait
            end
          end
        end

        logger.debug { "#{__method__} @last_cnx_state: #{@last_cnx_state.inspect}, time_left? #{timeout ? (Time.now.to_f < time_to_stop.to_f) : 'true'}, @client_state: #{@client_state.inspect}" }
      end


      # @private
      def client_state
        @mutex.synchronize { @client_state }
      end

      private
        # are we in running (not-paused) state?
        def running?
          @client_state == RUNNING
        end

        # are we in paused state?
        def paused?
          @client_state == PAUSED
        end

        # has shutdown time arrived?
        def close_requested?
          @client_state == CLOSE_REQ
        end

        def dead_or_dying?
          (@client_state == CLOSE_REQ) || (@client_state == CLOSED)
        end

        # this is just here so we can see it in stack traces
        def reopen_after_session_expired
          reopen
        end
        
        # in the threaded version of the client, synchronize access around cnx
        # so that callers don't wind up with a nil object when we're in the middle
        # of reopening it
        def cnx
          @mutex.synchronize { @cnx }
        end

        def reconnect_thread_body
          Thread.current[:name] = 'reconnect'
          while @reconnect  # too clever?
            @mutex.synchronize do
              # either we havne't seen a valid session update from this
              # connection yet, or we're doing fine, so just wait
              @cond.wait_while { !seen_session_state_event? or (valid_session_state? and running?) }

              # we've entered into a non-running state, so we exit
              # note: need to restart this thread after a fork in parent
              unless running?
                logger.debug { "session failure watcher thread exiting, @client_state: #{@client_state}" }
                return
              end

              # if we know that this session was valid once and it has now
              # become invalid we call reopen
              #
              if seen_session_state_event? and not valid_session_state?
                logger.debug { "session state was invalid, calling reopen" }

                # reopen will reset @last_cnx_state so that
                # seen_session_state_event? will return false until the first
                # event has been delivered on the new connection
                rv = reopen_after_session_expired

                logger.debug { "reopen returned: #{rv.inspect}" }
              end
            end
          end
        end

        def join_and_clear_reconnect_thread
          return unless @reconnect_thread
          begin
             # this should never time out but, just to make sure we don't hang forever
            unless @reconnect_thread.join(30)
              logger.error { "timed out waiting for reconnect thread to join! something is hosed!" }
            end
          rescue Exception => e
            logger.error { "caught exception joining reconnect thread" }
            logger.error { e.to_std_format }
          end
          @reconnect_thread = nil
        end

        def spawn_reconnect_thread
          @reconnect_thread ||= Thread.new(&method(:reconnect_thread_body))
        end

        def call_and_check_rc(meth, opts)
          if retry_duration = (opts.delete(:retry_duration) || @retry_duration)
            begin
              super(meth, opts)
            rescue Exceptions::Retryable => e
              time_to_stop = Time.now + retry_duration

              wait_until_connected_or_dying(retry_duration)

              if (@last_cnx_state != Zookeeper::ZOO_CONNECTED_STATE) || (Time.now > time_to_stop) || !running?
                raise e
              else
                retry
              end
            end
          else
            super
          end
        end

        # have we gotten a status event for the current connection?
        # this method is not synchronized
        def seen_session_state_event?
          !!@last_cnx_state
        end

        # we've seen a session state from the cnx, and it was not "omg we're screwed"
        # will return false if we havne't gotten a session event yet
        #
        # this method is not synchronized
        def valid_session_state?
          # this is kind of icky, but the SESSION_INVALID and AUTH_FAILED states
          # are both negative numbers
          @last_cnx_state and (@last_cnx_state >= 0)
        end

        def create_connection(*args)
          ::Zookeeper.new(*args)
        end

        def unlocked_connect(opts={})
          return if @cnx
          timeout = opts.fetch(:timeout, @connection_timeout)

          # this is a little bit of a lie, but is the legitimate state we're in when we first
          # create the connection.
          @last_cnx_state = Zookeeper::ZOO_CONNECTING_STATE

          @cnx = create_connection(@host, timeout, @event_handler.get_default_watcher_block, opts)

          spawn_reconnect_thread
          
          # this is a bit of a hack, because we need to wait until the event thread
          # delivers the connected event, which we used to be able to rely on just the
          # connection doing. since we don't want to call the @cnx.state method to check
          # (rather use the cached @last_cnx_state), we wait for consistency's sake
          #
          # NOTE: this may cause issues later if we move to using non-reentrant locks
          # TODO: this may wind up causing the whole process to take longer
          #       than `timeout` to complete, we should probably be using a difference
          #       (i.e. time-to-go) here
          wait_until_connected_or_dying(timeout) 
        end
    end # Threaded
  end # Client
end # ZK
