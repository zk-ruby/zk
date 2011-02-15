module ZK
  module Election
    VOTE_PREFIX = 'ballot'.freeze
    ROOT_NODE = '/_zkelection'.freeze

    class Base
      attr_reader :zk, :vote_path, :root_election_node

      def initialize(client, name, root_election_node=nil)
        @zk = client
        @name = name
        @root_election_node = (root_election_node || ROOT_NODE).dup.freeze
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
        @leader_ack_path ||= "#{@root_election_node}/leader_ack"
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
      def initialize(client, name, data=nil, root_election_node=nil)
        super(client, name, root_election_node)
        @leader = nil 
        @data   = data
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
          @zk.create(leader_ack_path, @data, :ephemeral => true)
        end

        # return the list of ephemeral vote nodes
        def get_ballots
          @zk.children(root_vote_path).tap do |ballots|
            ballots.sort! {|a,b| digit(a) <=> digit(b) }
          end
        end

        # if +watch_next+ is true, we register a watcher for the next-lowest
        # index number in the list of ballots
        #
        def check_election_results!
          return if leader?         # we already know we're the leader
          ballots = get_ballots()

#           $stderr.puts "#{@data} ballots: #{ballots.inspect}"

          our_idx = ballots.index(vote_basename)
          
          if our_idx == 0           # if we have the lowest number
            @leader = true  
            fire_winning_callbacks!

            if @current_leader_watch_sub
              @current_leader_watch_sub.unsubscribe 
              @current_leader_watch_sub = nil
            end

            acknowledge_win!
          else
            @leader = false

            fire_losing_callbacks!

            # we watch the next-lowest ballot, not the ack path
            leader_abspath = File.join(root_vote_path, ballots[our_idx - 1])

            @current_leader_watch_sub ||= @zk.watcher.register(leader_abspath) do |event| 
              if event.node_deleted? 
                vote! 
              else
                # this takes care of the race condition where the leader ballot would
                # have been deleted before we could re-register to receive updates
                # if zk.stat returns false, it means the path was deleted
                vote! unless @zk.stat(event.path, :watch => true).exists?
              end
            end

            # this catches a possible race condition, where the leader has died before
            # our callback has fired. In this case, retry and do this procedure again
            retry unless @zk.stat(leader_abspath, :watch => true).exists?
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
      def initialize(client, name, root_election_node=nil)
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

      protected
        def the_king_is_dead
          @mutex.synchronize do
#             $stderr.puts "the king is dead"
            @leader_death_cbs.each { |blk| blk.call }
            @leader_alive = false
          end

          long_live_the_king if leader_acked?(true)
        end

        def long_live_the_king
          @mutex.synchronize do
#             $stderr.puts "long live the king"
            @new_leader_cbs.each { |blk| blk.call }
            @leader_alive = true
          end

          the_king_is_dead unless leader_acked?(true)
        end
    end
  end
end
