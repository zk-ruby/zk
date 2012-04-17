module ZK
  # A ruby-friendly wrapper around the low-level zookeeper drivers. This is the
  # class that you will likely interact with the most. 
  #
  # @todo ACL support is pretty much unused currently. 
  #   If anyone has suggestions, hints, use-cases, examples, etc. by all means please file a bug.
  #
  module Client
    DEFAULT_TIMEOUT = 10

    # @private
    STATE_SYM_MAP = {
      Zookeeper::ZOO_CLOSED_STATE           => :closed,
      Zookeeper::ZOO_EXPIRED_SESSION_STATE  => :expired_session,
      Zookeeper::ZOO_AUTH_FAILED_STATE      => :auth_failed,
      Zookeeper::ZOO_CONNECTING_STATE       => :connecting,
      Zookeeper::ZOO_CONNECTED_STATE        => :connected,
      Zookeeper::ZOO_ASSOCIATING_STATE      => :associating,
    }.freeze

    def self.new(*a, &b)
      Threaded.new(*a, &b)
    end
  end
end

require 'z_k/client/drop_box'
require 'z_k/client/state_mixin'
require 'z_k/client/unixisms'
require 'z_k/client/conveniences'
require 'z_k/client/base'
require 'z_k/client/threaded'
require 'z_k/client/continuation_proxy'
require 'z_k/client/multiplexed'

