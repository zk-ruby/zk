module ZK
  module Client
    # This is the default client that ZK will use. In the zk-eventmachine gem,
    # there is an Evented client.
    class Threaded < Base
      include StateMixin
      include Unixisms
      include Conveniences

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
        yield self if block_given?
        @cnx = ::Zookeeper.new(host, DEFAULT_TIMEOUT, @event_handler.get_default_watcher_block)
        @threadpool = Threadpool.new
      end

      # closes the underlying connection and deregisters all callbacks
      def close!
        super
        @threadpool.shutdown
        nil
      end
    end
  end
end

