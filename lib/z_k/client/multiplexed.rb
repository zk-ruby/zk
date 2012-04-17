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

    end
  end
end

