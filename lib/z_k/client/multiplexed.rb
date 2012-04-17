
module ZK
  module Client
    # This client is an experimental implementation of a threaded and
    # multiplexed client. The idea is that each synchronous request represents 
    # a continuation. This way, you can have multiple requests pending with the
    # server simultaneously, and the responses will be delivered on the event
    # thread (but run in the calling thread). This allows for higher throughput
    # for multi-threaded applications.
    #
    # Asynchronous requests are not supported through this client.
    #
    class Multiplexed < Threaded
      def close!
        @cnx.connection_closed!
        super
      end

      protected
        def create_connection(*args)
          ConnectionProxy.new.tap do |cp|
            on_session_expired { cp.session_expired! } # hook up client's session expired event listener
            cp.zookeeper_cnx = super(*args)
          end
        end
    end
  end
end

