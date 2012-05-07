module ZK
  module Election
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

      # Asynchronously call the block when the leader has acknowledged its
      # role. 
      #
      # this is a one-shot callback. you must re-register after this callback fires
      #
      def on_leader_ack(&block)
        raise NotImplementedError, "Still need to implement parent-side subscriptions for on_leader_ack"
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
          @mutex.synchronize { yield }
        end
    end # Base
  end # Election
end # ZK
