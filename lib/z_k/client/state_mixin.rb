module ZK
  module Client
    # Provides client-state related methods. Included in ZK::Client::Base.
    # (refactored out to this class to ease documentation overload)
    module StateMixin
      # Returns true if the underlying connection is in the +connected+ state.
      def connected?
        wrap_state_closed_error { cnx and cnx.connected? }
      end

      # is the underlying connection is in the +associating+ state?
      # @return [bool]
      def associating?
        wrap_state_closed_error { cnx and cnx.associating? }
      end

      # is the underlying connection is in the +connecting+ state?
      # @return [bool]
      def connecting?
        wrap_state_closed_error { cnx and cnx.connecting? }
      end
      
      # is the underlying connection is in the +expired_session+ state?
      # @return [bool]
      def expired_session?
        return nil unless @cnx

        if defined?(::JRUBY_VERSION)
          cnx.state == Java::OrgApacheZookeeper::ZooKeeper::States::EXPIRED_SESSION
        else
          wrap_state_closed_error { cnx.state == Zookeeper::ZOO_EXPIRED_SESSION_STATE }
        end
      end

      # returns the current state of the connection as reported by the underlying driver
      # as a symbol. The possible values are <tt>[:closed, :expired_session, :auth_failed
      # :connecting, :connected, :associating]</tt>. 
      #
      # See the Zookeeper session 
      # {documentation}[http://hadoop.apache.org/zookeeper/docs/current/zookeeperProgrammers.html#ch_zkSessions]
      # for more information
      #
      def state
        if defined?(::JRUBY_VERSION) 
          cnx.state.to_string.downcase.to_sym
        else
          STATE_SYM_MAP.fetch(cnx.state) { |k| raise IndexError, "unrecognized state: #{k}" }
        end
      end

      # Register a block to be called on connection, when the client has
      # connected. 
      # 
      # the block will be called with no arguments
      #
      # returns an EventHandlerSubscription object that can be used to unregister
      # this block from further updates
      #
      def on_connected(&block)
        watcher.register_state_handler(:connected, &block)
      end

      # register a block to be called when the client is attempting to reconnect
      # to the zookeeper server. the documentation says that this state should be
      # taken to mean that the application should enter into "safe mode" and operate
      # conservatively, as it won't be getting updates until it has reconnected
      #
      def on_connecting(&block)
        watcher.register_state_handler(:connecting, &block)
      end

      # register a block to be called when our session has expired. This usually happens
      # due to a network partitioning event, and means that all callbacks and watches must
      # be re-registered with the server
      #
      # @todo need to come up with a way to test this
      def on_expired_session(&block)
        watcher.register_state_handler(:expired_session, &block)
      end

      protected
        def wrap_state_closed_error
          yield
        rescue RuntimeError => e
          # gah, lame error parsing here
          raise e unless e.message == 'zookeeper handle is closed'
          false
        end
    end
  end
end

