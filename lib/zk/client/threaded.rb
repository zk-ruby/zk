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
      include Logging

      DEFAULT_THREADPOOL_SIZE = 1

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

        @connection_timeout = opts.fetch(:timeout, DEFAULT_TIMEOUT) # maybe move this into superclass?
        @event_handler   = EventHandler.new(self, opts)

        @reconnect = opts.fetch(:reconnect, true)

        @mutex = Monitor.new

        @close_requested = false

        yield self if block_given?

        @mutex.synchronize do
          connect if opts.fetch(:connect, true)
        end
      end

      # @option opts [Fixnum] :timeout how long we will wait for the connection
      #   to be established. If timeout is nil, we will wait forever: *use
      #   carefully*.
      def connect(opts={})
        @mutex.synchronize do
          return if @cnx
          timeout = opts.fetch(:timeout, @connection_timeout)
          @cnx = create_connection(@host, timeout, @event_handler.get_default_watcher_block)
        end
      end

      # @private
      def pause
        @cnx && @cnx.pause
      end

      # @private
      def resume
        @cnx && @cnx.resume
      end

      # (see Base#reopen)
      def reopen(timeout=nil)
        # If we've forked, then we can call all sorts of normally dangerous 
        # stuff because we're the only thread. 
        if forked?
          # ok, just to sanity check here
          raise "[BUG] we hit the fork-reopening code in JRuby!!" if defined?(::JRUBY_VERSION)

          logger.debug { "#{self.class}##{__method__} reopening everything, fork detected!" }

#           old_cnx, @cnx = @cnx, nil
#           old_cnx.close! if old_cnx # && !old_cnx.closed?

          @cnx = nil

          @mutex = Monitor.new
          @threadpool.reopen_after_fork!      # prune dead threadpool threads after a fork()
          @event_handler.reopen_after_fork!
          @pid = Process.pid
        else
          @cnx.reopen(timeout)
        end

        @mutex.synchronize { @close_requested = false }
        connect
        state
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
          return if @close_requested
          @close_requested = true 
        end

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
          @threadpool.shutdown(2)
          super
        end

        shutdown_thread.join unless on_tpool

        nil
      end

      # {see Base#close}
      def close
        super
      end

      # (see Threadpool#on_threadpool?)
      def on_threadpool?
        @threadpool and @threadpool.on_threadpool?
      end

      # (see Threadpool#on_exception)
      def on_exception(&blk)
        @threadpool.on_exception(&blk)
      end

      # @private
      def raw_event_handler(event)
        return unless event.session_event?

        if event.client_invalid?
          return unless @reconnect

          @mutex.synchronize do
            unless @close_requested  # a legitimate shutdown case

              logger.error { "Got event #{event.state_name}, calling reopen(0)! things may be messed up until this works itself out!" }
               
              # reopen(0) means that we don't want to wait for the connection
              # to reach the connected state before returning
              reopen(0)
            end
          end
        end
      rescue Exception => e
        logger.error { "BUG: Exception caught in raw_event_handler: #{e.to_std_format}" } 
      end

      protected
        # @private
        def create_connection(*args)
          ::Zookeeper.new(*args)
        end
      end
  end
end
