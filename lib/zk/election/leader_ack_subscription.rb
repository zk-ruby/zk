module ZK
  module Election
    class LeaderAckSubscription < Subscription::Actor
      extend Forwardable

      def_delegators :parent, :leader_ack_path

      attr_reader :zk

      def initialize(zk, parent, block)
        super(parent, block)

        @zk = zk
        @creation_sub = nil

        @called = false

        setup_event_subscription
      end

      def unsubscribe
        synchronize do
          @creation_sub.unregister if @creation_sub
          super
        end
      end

      def call(*args)
        synchronize do
          @called = true
          super
          unsubscribe
        end
      end

      private
        def setup_event_subscription
          @creation_sub = zk.register(leader_ack_path) do |event|
          end # register

          if zk.exists?(leader_ack_path, :watch => true)
            logger.debug { "on_leader_ack, #{leader_ack_path} exists, calling block" }
            self.call
          end
        end # setup_event_subscription

        def leader_ack_handler(event)
          synchronize do
            return if @called # guard
          end
              
          if event.created? or event.changed?
            logger.debug { "in #{leader_ack_path} watcher, got creation event, notifying" }
            self.call
          elsif zk.exists?(leader_ack_path, :watch => true)
            logger.debug { "in #{leader_ack_path} watcher, node created behind our back, notifying" }
            self.call
          else
            logger.debug { "in #{leader_ack_path} watcher, got non-creation event, re-watching" }
          end
        end
    end # LeaderAckSubscription
  end # Election
end # ZK
