module ZK
  module Election
    VOTE_PREFIX = 'ballot'.freeze
    ROOT_NODE = '/_zkelection'.freeze

    VALID_FOLLOW_OPTIONS = [:next_node, :leader].freeze

    DEFAULT_OPTS = {
      :root_election_node => ROOT_NODE,
      :follow => :next_node,
    }.freeze
 
    class Base
     include Logging
      attr_reader :zk, :vote_path, :root_election_node

      def initialize(client, name, opts={})
        @zk = client
        @name = name
        opts = DEFAULT_OPTS.merge(opts)
        @root_election_node = opts[:root_election_node]
        @mutex = Monitor.new
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

      # (possibly) asynchronously call the block when the leader has acknowledged its role
      def on_leader_ack(&block)
        creation_sub = @zk.watcher.register(leader_ack_path) do |event|
          if event.node_created?
            begin
              logger.debug { "in #{leader_ack_path} watcher, got creation event, notifying" }
              block.call
            ensure
              creation_sub.unregister
            end
          else
            if @zk.exists?(leader_ack_path, :watch => true)
              begin
                logger.debug { "in #{leader_ack_path} watcher, node created behind our back, notifying" }
                block.call
              ensure
                creation_sub.unregister
              end
            else
              logger.debug { "in #{leader_ack_path} watcher, got non-creation event, re-watching" }
            end
          end
        end

        if @zk.exists?(leader_ack_path, :watch => true)
          logger.debug { "wait_for_leader_ack, #{leader_ack_path} exists, returning" }
          begin
            block.call
          ensure
            creation_sub.unregister if creation_sub
          end
        end
      end


      # waits for the leader_ack path to be created
      def wait_for_leader_ack #:nodoc:
        queue = Queue.new

        logger.debug { "wait_for_leader_ack, #{leader_ack_path} did not exist, waiting for creation" }
        queue.pop # wait for callback
        logger.debug { "wait_for_leader_ack, got notification, returning" }
      ensure
        creation_sub.unregister if creation_sub
      end

      protected
        def create_root_path!
          @zk.mkdir_p(root_vote_path)
        end

        def vote_basename
          vote_path and File.basename(vote_path)
        end

        def digit(path)
          path[/\d+$/].to_i
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

        @leader = nil 
        @data   = opts[:data] || ''

        unless VALID_FOLLOW_OPTIONS.include?(opts[:follow])
          raise ArgumentError, "Invalid :follow value: #{opts[:follow].inspect}"
        end

        @follow = opts[:follow]
        
        @winner_callbacks = []
        @loser_callbacks = []

        @current_leader_watch_sub = nil # the subscription for leader acknowledgement changes
      end

      def leader?
        @mutex.synchronize { false|@leader }
      end

      # true if leader has been determined at least once (used in tests)
      def voted? #:nodoc:
        @mutex.synchronize { !@leader.nil? }
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
      def on_takeover_error
        raise NotImplementedError
      end

      # volunteer to become the leader. if we win, on_winning_election blocks will
      # be called, otherwise, wait for next election
      #
      # +data+ will be placed in the znode representing our vote
      def vote!
        @mutex.synchronize do
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
            handle_losing_election
          end
        end

        def handle_winning_election
          @leader = true  
          fire_winning_callbacks!

          if @current_leader_watch_sub
            @current_leader_watch_sub.unsubscribe 
            @current_leader_watch_sub = nil
          end

          acknowledge_win!
        end

        def handle_losing_election
          @leader = false

          on_leader_ack do
            fire_losing_callbacks!

            follow_node =
              case @follow
              when :leader
                # watch the ack path, that way we get notified if the master goes away
                leader_ack_path
              when :next_node
                # we watch the next-lowest ballot, not the ack path, that way we only get
                # notified if we need to become the leader
                File.join(root_vote_path, ballots[our_idx - 1])
              end

            logger.info { "ZK: following #{follow_node} for changes, #{@data.inspect}" }

            @current_leader_watch_sub ||= @zk.watcher.register(follow_node) do |event| 
              if event.node_deleted? 
                logger.debug { "#{follow_node} was deleted, voting, #{@data.inspect}" }
                vote! 
              else
                # this takes care of the race condition where the leader ballot would
                # have been deleted before we could re-register to receive updates
                # if zk.stat returns false, it means the path was deleted
                unless @zk.stat(event.path, :watch => true).exists?
                  logger.debug { "#{follow_node} was deleted (detected on re-watch), voting, #{@data.inspect}" }
                  vote! 
                end
              end
            end

            # this catches a possible race condition, where the leader has died before
            # our callback has fired. In this case, retry and do this procedure again
            unless @zk.stat(follow_node, :watch => true).exists?
              logger.debug { "the node #{follow_node} did not exist, retrying, #{@data.inspect}" }
              return check_election_results!
            end
          end
        end

        def fire_winning_callbacks!
          @winner_callbacks.each { |blk| blk.call }
        end

        def fire_losing_callbacks!
          @loser_callbacks.each { |blk| blk.call }
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
        @mutex.synchronize { @leader_alive }
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
        @mutex.synchronize do
          return if @observing 
          @observing = true

          @deletion_sub ||= @zk.watcher.register(leader_ack_path) do |event|
            the_king_is_dead if event.node_deleted?
          end

          the_king_is_dead unless leader_acked?(true)

          @creation_sub ||= @zk.watcher.register(leader_ack_path) do |event|
            long_live_the_king if event.node_created?
          end

          long_live_the_king if leader_acked?(true)
        end
      end

      def close
        @mutex.synchronize do
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
          @mutex.synchronize do
            @leader_death_cbs.each { |blk| blk.call }
            @leader_alive = false
          end

          long_live_the_king if leader_acked?(true)
        end

        def long_live_the_king
          @mutex.synchronize do
            @new_leader_cbs.each { |blk| blk.call }
            @leader_alive = true
          end

          the_king_is_dead unless leader_acked?(true)
        end
    end
  end
end
