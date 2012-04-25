module ZK
  module Client
    # This is the default client that ZK will use. In the zk-eventmachine gem,
    # there is an Evented client.
    #
    # If you want to register `on_*` callbacks (see ZK::Client::StateMixin)
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
    # The configurability is intended to allow users to easily dispatch events to
    # event handlers that will perform (application specific) work. Be aware,
    # the default will give you the guarantee that only one event will be delivered
    # at a time. The advantage to this is that you can be sure that no event will 
    # be delivered "behind your back" while you're in an event handler. If you're
    # comfortable with dealing with threads and concurrency, then feel free to 
    # set the `:threadpool_size` option to the constructor to a value you feel is
    # correct for your app. 
    # 
    # If you use the threadpool/event callbacks to perform work, you may be
    # interested in registering an `on_exception` callback that will receive
    # all exceptions that occur on the threadpool that are not handled (i.e.
    # that bubble up to top of a block).
    #
    # It is recommended that you not run any possibly long-running work on the
    # event threadpool, as `close!` will attempt to shutdown the threadpool, and
    # **WILL NOT WAIT FOREVER**. (TODO: more on this)
    # 
    #
    # @example Register on_connected callback.
    #   
    #   # the nice thing about this pattern is that in the case of a call to #reopen
    #   # all your watches will be re-established
    #
    #   ZK::Client::Threaded.new('localhsot:2181') do |zk|
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
      #   configurable, but still defaults to 1. (The Management apologizes for
      #   any confusion this may have caused).
      #
      # @param [String] host (see ZK::Client::Base#initialize)
      #
      # @option opts [true,false] :reconnect (true) if true, we will register
      #   the equivalent of `on_session_expired { zk.reopen }` so that in the
      #   case of an expired session, we will keep trying to reestablish the
      #   connection.
      #
      # @option opts [Fixnum] :threadpool_size (1) the size of the threadpool that
      #   should be used to deliver events. As of 1.0, this is the number of
      #   event delivery threads and controls the amount of concurrency in your
      #   app if you're doing work in the event callbacks.
      #
      # @option opts [Fixnum] :timeout how long we will wait for the connection
      #   to be established. If timeout is nil, we will wait forever *use
      #   carefully*.
      #
      # @yield [self] calls the block with the new instance after the event
      #   handler and threadpool have been set up, but before any connections
      #   have been made.  This allows the client to register watchers for
      #   session events like `connected`. You *cannot* perform any other
      #   operations with the client as you will get a NoMethodError (the
      #   underlying connection is nil).
      #
      def initialize(host, opts={}, &b)
        super(host, opts)

        tp_size = opts.fetch(:threadpool_size, DEFAULT_THREADPOOL_SIZE)
        @threadpool = Threadpool.new(tp_size)

        @session_timeout = opts.fetch(:timeout, DEFAULT_TIMEOUT) # maybe move this into superclass?
        @event_handler   = EventHandler.new(self)

        @reconnect = opts.fetch(:reconnect, true)

        @mutex = Mutex.new

        @close_requested = false

        yield self if block_given?

        @cnx = create_connection(host, @session_timeout, @event_handler.get_default_watcher_block)
      end

      def reopen(timeout=nil)
        @mutex.synchronize { @close_requested = false }
        super
      end

      # (see ZK::Client::Base#close!)
      def close!
        @mutex.synchronize do 
          return if @close_requested
          @close_requested = true 
        end

        if event_dispatch_thread?
          msg = ["ZK ERROR: You called #{self.class}#close! on event dispatch thread!!",
                 "This will cause the client to deadlock and possibly your main thread as well!"]

          warn_msg = [nil, msg, nil, "See ZK error log output (stderr by default) for a backtrace", nil].join("\n")

          Kernel.warn(warn_msg)
          assert_we_are_not_on_the_event_dispatch_thread!(msg.join(' '))
        end

        @threadpool.shutdown

        super

        nil
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
        # allows for the Mutliplexed client to wrap the connection in its ContinuationProxy
        # @private
        def create_connection(*args)
          ::Zookeeper.new(*args)
        end
      end
  end
end
