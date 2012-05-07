module ZK
  module Election
    class Observer < Base
      def initialize(client, name, opts={})
        super
        @leader_death_cbs = []
        @new_leader_cbs = []
        @deletion_sub = @creation_sub = nil
        @leader_alive = nil
        @observing = false
      end

      # our current idea about the state of the election
      def leader_alive #:nodoc:
        synchronize { @leader_alive }
      end

      # register callbacks that should be fired when a leader dies
      def on_leaders_death(&blk)
        @leader_death_cbs << blk
      end

      # register callbacks for when the new leader has acknowledged their role
      # returns a subscription object that can be used to cancel further events
      def on_new_leader(&blk)
        @new_leader_cbs << blk
      end

      def observe!
        synchronize do
          return if @observing 
          @observing = true

          @leader_ack_sub ||= @zk.register(leader_ack_path) do |event|
            logger.debug { "leader_ack_callback, event.node_deleted? #{event.node_deleted?}, event.node_created? #{event.node_created?}" }

            if event.node_deleted?
              the_king_is_dead 
            elsif event.node_created?
              long_live_the_king
            else
              acked = leader_acked?(true) 


              # If the current state of the system is not what we think it should be
              # a transition has occurred and we should fire our callbacks
              if (acked and !@leader_alive)
                long_live_the_king 
              elsif (!acked and @leader_alive)
                the_king_is_dead
              else
                # things are how we think they should be, so just wait for the
                # watch to fire
              end
            end
          end

          leader_acked?(true) ? long_live_the_king : the_king_is_dead
        end
      end

      def close
        synchronize do
          return unless @observing

          @deletion_sub.unregister if @deletion_sub
          @creation_sub.unregister if @creation_sub

          @deletion_sub = @creation_sub = nil

          @leader_death_cbs.clear
          @new_leader_cbs.clear

          @leader_alive = nil
          @observing = false
        end
      end

      protected
        def the_king_is_dead
          synchronize do
            safe_call(*@leader_death_cbs)
            @leader_alive = false
          end

          long_live_the_king if leader_acked?(true)
        end

        def long_live_the_king
          synchronize do
            safe_call(*@new_leader_cbs)
            @leader_alive = true
          end

          the_king_is_dead unless leader_acked?(true)
        end
    end # Observer
  end # Election
end # ZK

