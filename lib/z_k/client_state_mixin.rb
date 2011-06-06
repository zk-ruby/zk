module ZK
  module ClientStateMixin
    # Returns true if the underlying connection is in the +connected+ state.
    def connected?
      wrap_state_closed_error { @cnx and @cnx.connected? }
    end

    # is the underlying connection is in the +associating+ state?
    # @return [bool]
    def associating?
      wrap_state_closed_error { @cnx and @cnx.associating? }
    end

    # is the underlying connection is in the +connecting+ state?
    # @return [bool]
    def connecting?
      wrap_state_closed_error { @cnx and @cnx.connecting? }
    end

    # is the underlying connection is in the +expired_session+ state?
    # @return [bool]
    def expired_session?
      return nil unless @cnx

      if defined?(::JRUBY_VERSION)
        @cnx.state == Java::OrgApacheZookeeper::ZooKeeper::States::EXPIRED_SESSION
      else
        wrap_state_closed_error { @cnx.state == Zookeeper::ZOO_EXPIRED_SESSION_STATE }
      end
    end
  end
end

