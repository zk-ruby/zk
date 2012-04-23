module ZK
  module Client
    # This is the default client that ZK will use. In the zk-eventmachine gem,
    # there is an Evented client.
    #
    class Threaded < Base
      include StateMixin
      include Unixisms
      include Conveniences

      DEFAULT_THREADPOOL_SIZE = 1

      # @note The `:timeout` argument here is *not* the session_timeout for the
      #   connection. rather it is the amount of time we wait for the connection
      #   to be established. The session timeout exchanged with the server is 
      #   set to 10s by default in the C implemenation, and as of version 0.8.0 
      #   of slyphon-zookeeper has yet to be exposed as an option. That feature
      #   is planned. 
      #
      # @param [String] host (see ZK::Client::Base#initialize)
      #
      # @option opts [Fixnum] :threadpool_size the size of the threadpool that
      #   should be used to deliver events. In ZK 0.8.x this was set to 5, which
      #   means that events could be delivered concurrently. As of 0.9, this will
      #   be set to 1, so it's very important to _not block the event thread_.
      #
      # @option opts [Fixnum] :timeout how long we will wait for the connection
      #   to be established. 
      #
      # @yield [self] calls the block with the new instance after the event
      #   handler has been set up, but before any connections have been made.
      #   This allows the client to register watchers for session events like
      #   `connected`. You *cannot* perform any other operations with the client 
      #   as you will get a NoMethodError (the underlying connection is nil).
      #
      def initialize(host, opts={}, &b)
        super(host, opts)

        @session_timeout = opts.fetch(:timeout, DEFAULT_TIMEOUT) # maybe move this into superclass?
        @event_handler   = EventHandler.new(self)

        yield self if block_given?

        @cnx = create_connection(host, @session_timeout, @event_handler.get_default_watcher_block)

        tp_size = opts.fetch(:threadpool_size, DEFAULT_THREADPOOL_SIZE)

        @threadpool = Threadpool.new(tp_size)
      end

      # @see ZK::Client::Base#close!
      def close!
        @threadpool.shutdown
        super
        nil
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
