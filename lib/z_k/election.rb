module ZK
  module Election
    attr_reader :zk, :vote_path

    VOTE_PREFIX = 'ballot'.freeze
    ROOT_NODE = '/_zkelection'.freeze

    class Base
      def initialize(client, name, root_election_node=nil)
        @zk = client
        @name = name
        @root_election_node = root_election_node || ROOT_NODE
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

      # register callbacks that should be fired when a leader dies
      def on_leaders_death(&blk)
        @zk.watcher.register(leader_ack_path) do |event,zk|
          if event.state_deleted?
            blk.call(event, zk)
            leader_acked?(true) # renew watch
          end
        end
      end

      # register callbacks for when the new leader has acknowledged their role
      # returns a subscription object that can be used to cancel further events
      def on_new_leader_ack(&blk)
        cb = lambda do 
          if event.state_created?
            blk.call
            leader_acked?(true)
          end
        end

        # XXX: not sure this is correct here
        @zk.watcher.register(leader_ack_path, cb).tap do
          cb.call if leader_acked?(true)
        end
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
        false|@zk.exists?(leader_ack_path, :watch => watch)
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
        super
        @leader = false
        @data   = data
        @winner_callbacks = []
      end

      def leader?
        false|@leader
      end
      
      # When we win the election, we will call the procs registered using this
      # method.
      def on_winning_election(&block)
        @winner_callbacks << block
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
        cast_ballot!(@data) unless @vote_path
        check_election_results!
      end

      protected
        # the inauguration, as it were
        def acknowledge_win!
          @zk.create(leader_ack_path, @data, :ephemeral => true)
        end

        # if +watch_next+ is true, we register a watcher for the next-lowest
        # index number in the list of ballots
        #
        def check_election_results!
          ballots = @zk.children(root_vote_path)
          ballots.sort! {|a,b| digit(a) <=> digit(b) }

          our_idx = ballots.index(vote_basename)
          
          if our_idx == 0           # if we have the lowest number
            @leader = true  
            fire_winning_callbacks!
          else
            leader_abspath = File.join(root_vote_path, ballots[our_idx - 1])
            @zk.stat(leader_abspath, :watch => true)
          end
        end

        def fire_winning_callbacks!
          @winner_callbacks.each { |blk| blk.call }
        end
    end

    class Observer < Base
    end
  end
end
