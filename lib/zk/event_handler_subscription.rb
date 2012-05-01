module ZK
  # the subscription object that is passed back from subscribing
  # to events.
  # @see ZK::Client::Base#register
  module EventHandlerSubscription

    # @private
    def self.class_for_thread_option(thopt)
      case thopt
      when :single
        Base
      when :per_callback
        Actor
      else
        raise ArgumentError, "Unrecognized :thread option: #{thopt}"
      end
    end

    def self.new(*a, &b)
      opts = a.extract_options!
 
      klass = class_for_thread_option(opts.delete(:thread))

      a << opts
      klass.new(*a, &b)
    end
  end
end

require 'zk/event_handler_subscription/base'
require 'zk/event_handler_subscription/actor'

