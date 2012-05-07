module ZK
  # @note this module should be considered experimental. 
  #
  # This module implements the "leader election" protocols described
  # [here](http://hadoop.apache.org/zookeeper/docs/current/recipes.html#sc_leaderElection).
  #
  # There are {ZK::Election::Candidates Candidates} and {ZK::Election::Observers Observers}. 
  # Candidates take part in elections and all have equal ability and chance to
  # become the leader. When a leader is decided, they hold onto the leadership
  # role until they die. When the leader dies, an election is held and the
  # winner has its +on_winning_election+ callbacks fired, and the losers have
  # their +on_losing_election+ callbacks fired. When all of the
  # `on_winning_election` callbacks have completed (completing whatever steps
  # are necessary to assume the leadership role), the leader will "acknowledge"
  # that it has taken over by creating an ephemeral node at a known location
  # (with optional data that the Observers can then read and take action upon).
  # Note that when this node is created, it means the *leader* has finished
  # taking over, but it does *not* mean that all the slaves have completed
  # *their* tasks.
  #
  # Observers are interested parties in the election, the "constituents" of the
  # process. They can register callbacks to be fired when a new leader has been
  # elected and when a leader has died. The new leader callbacks will only fire
  # once the leader has acknowledged its role, so they can be sure that the
  # leader is ready to perform its duties.
  #
  #
  # One problem this pattern can be used to solve is failover between two
  # database nodes. Candidates set up callbacks to both take over as master
  # and to follow the master if they lose the election. On the client side,
  # Obesrvers are set up to follow the "leader ack" node. The leader writes its
  # connection info to the "leader ack" node, and the clients can reconnect to
  # the currently active leader.
  #
  # @example 
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
  #   # Note that as soon as vote! is called, either the on_winning_election or
  #   # on_losing_election callbacks will be called. 
  #
  #
  module Election
    VOTE_PREFIX = 'ballot'.freeze
    ROOT_NODE = '/_zkelection'.freeze

    VALID_FOLLOW_OPTIONS = [:next_node, :leader].freeze

    DEFAULT_OPTS = {
      :root_election_node => ROOT_NODE,
    }.freeze
 
  end # Election
end # ZK

require 'zk/election/base'
require 'zk/election/result_subscription'
require 'zk/election/candidate'
require 'zk/election/observer'

