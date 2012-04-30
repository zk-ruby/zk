module ZK
  # the subscription object that is passed back from subscribing
  # to events.
  # @see ZK::Client::Base#register
  module EventHandlerSubscription
    def self.new(*a, &b)
      opts = a.extract_options!
      opts[:actor] ? Actor.new(*a, &b) : Base.new(*a, &b)
    end
  end
end

require 'zk/event_handler_subscription/base'
require 'zk/event_handler_subscription/actor'

