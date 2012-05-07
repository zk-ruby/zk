module ZK
  module Election
    # This class is for registering candidates in the leader election. This instance will
    # participate in votes for becoming the leader and will be notified in the
    # case where it needs to take over.
    #
    # if data is given, it will be used as the content of both our ballot and
    # the leader acknowledgement node if and when we become the leader.
    class Candidate < Base
      def initialize(client, name, opts={})
        super(client, name, opts)
        opts = DEFAULT_OPTS.merge(opts)

        @leader     = nil 
        @data       = opts[:data] || ''
        @vote_path  = nil
        
        @winner_callbacks = []
        @loser_callbacks = []

        @next_node_ballot_sub = nil # the subscription for next-node failure
      end

      def leader?
        false|@leader
      end

      # true if leader has been determined at least once (used in tests)
      def voted? #:nodoc:
        !@leader.nil?
      end
      
      # When we win the election, we will call the procs registered using this
      # method.
      def on_winning_election(&block)
        ResultSubscription.new(self, block).tap do |sub|
          synchronize { @winner_callbacks << sub }
        end
      end

      # When we lose the election and are relegated to the shadows, waiting for
      # the leader to make one small misstep, where we can finally claim what
      # is rightfully ours! MWUAHAHAHAHAHA(*cough*)
      def on_losing_election(&block)
        ResultSubscription.new(self, block).tap do |sub|
          synchronize { @loser_callbacks << sub }
        end
      end

      # These procs should be run in the case of an error when trying to assume
      # the leadership role. This should *probably* be a "hara-kiri" or STONITH
      # type procedure (i.e. kill the candidate)
      #
      def on_takeover_error #:nodoc:
        raise NotImplementedError
      end

      # volunteer to become the leader. if we win, on_winning_election blocks will
      # be called, otherwise, wait for next election
      #
      # +data+ will be placed in the znode representing our vote
      def vote!
        synchronize do
          clear_next_node_ballot_sub!
          cast_ballot!(@data) unless @vote_path
          check_election_results!
        end
      end

      protected
        # the inauguration, as it were
        def acknowledge_win!
          @zk.create(leader_ack_path, @data, :ephemeral => true) rescue Exceptions::NodeExists
        end

        # return the list of ephemeral vote nodes
        def get_ballots
          @zk.children(root_vote_path).grep(/^ballot/).tap do |ballots|
            ballots.sort! {|a,b| digit(a) <=> digit(b) }
          end
        end

        # if +watch_next+ is true, we register a watcher for the next-lowest
        # index number in the list of ballots
        #
        def check_election_results!
          #return if leader?         # we already know we're the leader
          ballots = get_ballots()

          our_idx = ballots.index(vote_basename)
          
          if our_idx == 0           # if we have the lowest number
            logger.info { "ZK: We have become leader, data: #{@data.inspect}" }
            handle_winning_election
          else
            logger.info { "ZK: we are not the leader, data: #{@data.inspect}" }
            handle_losing_election(our_idx, ballots)
          end
        end

        def handle_winning_election
          @leader = true  
          fire_winning_callbacks!
          acknowledge_win!
        end

        def handle_losing_election(our_idx, ballots)
          @leader = false

          on_leader_ack do
            fire_losing_callbacks!

            next_ballot = File.join(root_vote_path, ballots[our_idx - 1])

            logger.info { "ZK: following #{next_ballot} for changes, #{@data.inspect}" }

            @next_node_ballot_sub ||= @zk.register(next_ballot) do |event| 
              if event.node_deleted? 
                logger.debug { "#{next_ballot} was deleted, voting, #{@data.inspect}" }
                @zk.defer { vote! }
              else
                # this takes care of the race condition where the leader ballot would
                # have been deleted before we could re-register to receive updates
                # if zk.stat returns false, it means the path was deleted
                unless @zk.exists?(next_ballot, :watch => true)
                  logger.debug { "#{next_ballot} was deleted (detected on re-watch), voting, #{@data.inspect}" }
                  @zk.defer { vote! }
                end
              end
            end

            # this catches a possible race condition, where the leader has died before
            # our callback has fired. In this case, retry and do this procedure again
            unless @zk.stat(next_ballot, :watch => true).exists?
              logger.debug { "#{@data.inspect}: the node #{next_ballot} did not exist, retrying" }
              @zk.defer { vote! }
            end
          end
        end

        def clear_next_node_ballot_sub!
          if @next_node_ballot_sub
            @next_node_ballot_sub.unsubscribe 
            @next_node_ballot_sub = nil
          end
        end

        def fire_winning_callbacks!
          safe_call(*@winner_callbacks)
        end

        def fire_losing_callbacks!
          safe_call(*@loser_callbacks)
        end
    end # Candidate
  end # Election
end # ZK
