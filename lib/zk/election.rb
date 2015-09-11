module ZK
  # NOTE: this module should be considered experimental.
  #
  # ==== Overview
  #
  # This module implements the "leader election" protocols described
  # {here}[http://hadoop.apache.org/zookeeper/docs/current/recipes.html#sc_leaderElection].
  #
  # There are Candidates and Observers. Candidates take part in elections and
  # all have equal ability and chance to become the leader. When a leader is
  # decided, they hold onto the leadership role until they die. When the leader
  # dies, an election is held and the winner has its +on_winning_election+
  # callbacks fired, and the losers have their +on_losing_election+ callbacks
  # fired. When all of the +on_winning_election+ callbacks have completed
  # (completing whatever steps are necessary to assume the leadership role),
  # the leader will "acknowledge" that it has taken over by creating an
  # ephemeral node at a known location (with optional data that the Observers
  # can then read and take action upon). Note that when this node is created,
  # it means the *leader* has finished taking over, but it does *not* mean that
  # all the slaves have completed *their* tasks.
  #
  # Observers are interested parties in the election, the "constituents" of the
  # process. They can register callbacks to be fired when a new leader has been
  # elected and when a leader has died. The new leader callbacks will only fire
  # once the leader has acknowledged its role, so they can be sure that the
  # leader is ready to perform its duties.
  #
  # ==== Use Case / Example
  #
  # One problem this pattern can be used to solve is failover between two
  # database nodes. Candidates set up callbacks to both take over as master
  # and to follow the master if they lose the election. On the client side,
  # Obesrvers are set up to follow the "leader ack" node. The leader writes its
  # connection info to the "leader ack" node, and the clients can reconnect to
  # the currently active leader.
  #
  #
  #   def server
  #     candidate = @zk.election_candidate("database_election", "dbhost2.fqdn.tld:4567", :follow => :leader)
  #     candidate.on_winning_election { become_master_node! }
  #     candidate.on_losing_election { become_slave_of_master! }
  #
  #     @zk.on_connected do
  #       candidate.vote!
  #     end
  #   end
  #
  # Note that as soon as vote! is called, either the on_winning_election or
  # on_losing_election callbacks will be called. 
  #
  #
  module Election
    VOTE_PREFIX = 'ballot'.freeze
    ROOT_NODE = '/_zkelection'.freeze

    VALID_FOLLOW_OPTIONS = [:next_node, :leader].freeze

    DEFAULT_OPTS = {
      :root_election_node => ROOT_NODE,
    }.freeze
 
    class Base
     include Logger

     attr_reader :zk, :vote_path, :root_election_node

      def initialize(client, name, opts={})
        @zk = client
        @name = name
        opts = DEFAULT_OPTS.merge(opts)
        @root_election_node = opts[:root_election_node]
        @mutex = Monitor.new
        @closed = false
      end

      def close
        @mutex.synchronize do
          return if @closed
          @closed = true
        end
      end

      # holds the ephemeral nodes of this election
      def root_vote_path #:nodoc:
        @root_vote_path ||= "#{@root_election_node}/#{@name.gsub('/', '__')}"
      end

      # this znode will be created as an acknowledgement by the leader 
      # that it's aware of its status as the new leader and has run its 
      # procedures to become master
      def leader_ack_path
        @leader_ack_path ||= "#{root_vote_path}/leader_ack"
      end
     
      def cast_ballot!(data)
        return if @vote_path
        create_root_path!
        @vote_path = @zk.create("#{root_vote_path}/#{VOTE_PREFIX}", data, :mode => :ephemeral_sequential)
      rescue Exceptions::NoNode
        retry
      end
      
      # has the leader acknowledged their role?
      def leader_acked?(watch=false)
        @zk.exists?(leader_ack_path, :watch => watch)
      end
      
      # return the data from the current leader or nil if there is no current leader
      def leader_data
        @zk.get(leader_ack_path).first
      rescue Exceptions::NoNode
      end

      # Asynchronously call the block when the leader has acknowledged its
      # role. 
      def on_leader_ack(&block)
        creation_sub = @zk.register(leader_ack_path, :only => [:created, :changed]) do |event|
          return if @closed
          begin
            logger.debug { "in #{leader_ack_path} watcher, got creation event, notifying" }
            safe_call(block)
          ensure
            creation_sub.unregister
          end
        end

        deletion_sub = @zk.register(leader_ack_path, :only => [:deleted, :child]) do |event|
          if @zk.exists?(leader_ack_path, :watch => true)
            return if @closed
            begin
              logger.debug { "in #{leader_ack_path} watcher, node created behind our back, notifying" }
              safe_call(block)
            ensure
              creation_sub.unregister
            end
          else
            logger.debug { "in #{leader_ack_path} watcher, got non-creation event, re-watching" }
          end
        end

        subs = [creation_sub, deletion_sub]

        if @zk.exists?(leader_ack_path, :watch => true)
          logger.debug { "on_leader_ack, #{leader_ack_path} exists, calling block" }
          begin
            safe_call(block)
          ensure
            subs.each { |s| s.unregister }
          end
        end
      end

      private
        def create_root_path!
          @zk.mkdir_p(root_vote_path)
        end

        def vote_basename
          vote_path and File.basename(vote_path)
        end

        def digit(path)
          path[/\d+$/].to_i
        end

        def safe_call(*callbacks)
          callbacks.each do |cb|
            begin
              cb.call
            rescue Exception => e
              logger.error { "Error caught in user supplied callback" }
              logger.error { e.to_std_format }
            end
          end
        end

        def synchronize
#           call_line = caller[0..-2]
#           logger.debug { "synchronizing, backtrace:\n#{call_line.join("\n")}" }
          @mutex.synchronize { yield }
        end
    end

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
        @winner_callbacks << block
      end

      # When we lose the election and are relegated to the shadows, waiting for
      # the leader to make one small misstep, where we can finally claim what
      # is rightfully ours! MWUAHAHAHAHAHA(*cough*)
      def on_losing_election(&block)
        @loser_callbacks << block
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

      private
        # the inauguration, as it were
        def acknowledge_win!
          @zk.create(leader_ack_path, @data, :ephemeral => true) 
        rescue Exceptions::NodeExists
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
          @mutex.synchronize { return if @closed }
          @leader = true  
          fire_winning_callbacks!
          acknowledge_win!
        end

        def handle_losing_election(our_idx, ballots)
          @mutex.synchronize { return if @closed }

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
    end

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

      private
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
    end
  end # Election
end # ZK
