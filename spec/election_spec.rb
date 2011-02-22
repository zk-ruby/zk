require File.join(File.dirname(__FILE__), %w[spec_helper])
require 'pp'

describe ZK::Election do
  before do
    ZK.open('localhost:2181') do |cnx| 
      ZK.logger.debug { "REMOVING /_zkelection" }
      cnx.rm_rf('/_zkelection')
    end

    @zk = ZK.new('localhost:2181')
    @zk2 = ZK.new('localhost:2181')
    @election_name = '2012'
    @data1 = 'obama'
    @data2 = 'palin'
  end

  after do
    @zk.close!
    @zk2.close!

    ZK.open('localhost:2181') { |cnx| cnx.rm_rf('/_zkelection') }
  end

  describe 'Candidate', 'following next_node' do
    before do
      @obama = ZK::Election::Candidate.new(@zk, @election_name, :data => @data1)
      @palin = ZK::Election::Candidate.new(@zk2, @election_name, :data => @data2)
    end

    describe 'vote!' do
      describe 'loser' do
        it %[should wait until the leader has acked before firing loser callbacks] do
          queue = Queue.new
          @do_ack = false

          @obama_won = nil
          @palin_lost = nil

          @obama_waiting = nil

          @obama.on_winning_election do
            @obama_waiting = true

            # wait for us to signal
            queue.pop

            $stderr.puts "obama on_winning_election entered"
            @obama_won = true
          end

          @palin.on_losing_election do
            @obama_won.should be_true
            @palin.leader_acked?.should be_true
            @palin_lost = true
          end

          oth = Thread.new do
            @obama.vote!
            @palin.vote!
          end
          oth.run

          wait_until { @obama_waiting }
          @obama_waiting.should be_true

          # palin's callbacks haven't fired
          @palin_lost.should be_nil

          queue << :ok

          wait_until { @obama_won }
          @obama_won.should be_true

          lambda { oth.join(1).should == oth }.should_not raise_error

          wait_until { @palin_lost }

          @palin_lost.should be_true
        end
      end

      describe do
        before do
          @obama_won = @obama_lost = @palin_won = @palin_lost = nil

          @obama.on_winning_election do 
            @obama_won = true
          end

          @obama.on_losing_election do
            @obama_lost = true
          end

          @palin.on_winning_election do
            @palin_won = true
          end

          @palin.on_losing_election do
            @palin_lost = true
          end
          
          @obama.vote!
          @palin.vote!

          wait_until { @obama_won }
          wait_until { @palin_lost }
        end

        describe 'winner' do
          it %[should fire the on_winning_election callbacks] do
            @obama_won.should be_true
          end

          it %[should not fire the on_losing_election callbacks] do
            @obama_lost.should be_nil
          end

          it %[should acknowledge completion of winning callbacks] do
            @zk.exists?(@obama.leader_ack_path).should be_true
          end

          it %[should write its data to the leader_ack node] do
            @zk.get(@obama.leader_ack_path).first.should == @data1
          end

          it %[should know it's the leader] do
            @obama.should be_leader
          end
        end

        describe 'loser' do # gets a talk show on Fox News? I KEED! I KEED!
          it %[should know it isn't the leader] do
            @palin.should_not be_leader
          end

          it %[should not fire the winning callbacks] do
            @palin_won.should_not be_true
          end

          it %[should fire the losing callbacks] do
            @palin_lost.should be_true
          end

          it %[should take over as leader when the current leader goes away] do
            @zk.close!
            wait_until { @palin_won }

            @palin_won.should be_true # god forbid
            @zk2.exists?(@palin.leader_ack_path).should be_true
            @zk2.get(@palin.leader_ack_path).first.should == @data2
          end

          it %[should remain leader if the original leader comes back] do
            @zk.close!
            wait_until { @palin_won }

            zk = ZK.new('localhost:2181')
            newbama = ZK::Election::Candidate.new(zk, @election_name, :data => @data1)

            win_again = false

            newbama.on_winning_election do
              win_again = true
            end

            newbama.vote!
            wait_until { newbama.voted? }

            newbama.should be_voted
            win_again.should be_false
            newbama.should_not be_leader
          end
        end
      end
    end
  end

#   describe :Candidate, 'following leader' do
#     before do
#       @zk3 = ZK.new('localhost:2181')

#       @data1, @data2, @data3 = 'node1', 'node2', 'node3'

#       @node1 = @zk.election_candidate(@election_name, @data1, :follow => :leader)
#       @node2 = @zk2.election_candidate(@election_name, @data2, :follow => :leader)
#       @node3 = @zk3.election_candidate(@election_name, @data3, :follow => :leader)
#     end

#     after do
#       @zk3.close!
#     end

#     describe 'all nodes' do
#       it %[should notice the leadership change] do
#         @events = []
#         @node1.on_winning_election { @events << :node1_win }
#         @node1.on_losing_election { @events << :node1_lose }

#         @node2.on_winning_election { @events << :node2_win }
#         @node2.on_losing_election do 
#           logger.debug { "node2 callback registry" }
#           logger.debug { PP.pp(@node2.zk.event_handler.callbacks, '') }
#           @events << :node2_lose
#         end

#         @node3.on_winning_election do 
#           @events << :node3_win
#         end

#         @node3.on_losing_election do 
#           logger.debug { "node3 callback registry" }
#           logger.debug { PP.pp(@node3.zk.event_handler.callbacks, '') }
#           @events << :node3_lose
#         end

#         logger.debug { "node1 voting" }
#         @node1.vote!
#         wait_until { @node1.voted? }
#         @node1.should be_leader

#         logger.debug { "node2 voting" }
#         @node2.vote!
#         wait_until { @node2.voted? }
#         @node2.should_not be_leader

#         logger.debug { "node3 voting" }
#         @node3.vote!

#         wait_until { @node3.voted? }
#         logger.debug { "node3 voted" }

#         @node3.should_not be_leader
#         logger.debug { "node3 is not leader" }

#         wait_until { @events.length == 3 }
#         @events.length.should == 3

#         logger.debug { "@events:  #{@events.inspect}" }
#         @events.should include(:node1_win) 
#         @events.should include(:node2_lose)
#         @events.should include(:node3_lose)

#         @events.clear

#         logger.debug { "cleared events, closing @zk" }
#         @zk.close!
#         wait_until { !@zk.connected? }

#         logger.debug { "@zk closed!" }

#         wait_until { @events.length == 2 }
#         @events.length.should == 2

#         logger.debug { "@events: #{@events.inspect}" }
#         @events.should == [:node2_win, :node3_lose]

#         logger.debug { "clearing events" }
#         @events.clear
#       end
#     end
#   end

  describe :Observer do
    before do
      @zk3 = ZK.new('localhost:2181')

      @zk3.exists?('/_zkelection/2012/leader_ack').should be_false

      @obama = ZK::Election::Candidate.new(@zk, @election_name, :data => @data1)
      @palin = ZK::Election::Candidate.new(@zk2, @election_name, :data => @data2)

      @zk3.exists?('/_zkelection/2012/leader_ack').should be_false

      @observer = ZK::Election::Observer.new(@zk3, @election_name)
    end

    after do
      @zk3.close!
    end

    describe 'initial state' do
      describe 'no leader' do
        before do
          @events = []

          @observer.on_leaders_death { @events << :death }
          @observer.on_new_leader { @events << :life }

          @observer.observe!
          wait_until { !@observer.leader_alive.nil? }
          @observer.leader_alive.should_not be_nil
          @zk3.exists?(@observer.root_election_node).should be_false
        end

        it %[should set leader_alive to false] do
          @observer.leader_alive.should be_false
        end

        it %[should fire death callbacks] do
          @events.length.should == 1
          @events.first.should == :death
        end
      end

      describe 'leader exists before' do
        before do
          @obama.vote!
          @palin.vote!

          wait_until { @obama.leader? }

          logger.debug { "obama is the leader" }

          @got_life_event = @got_death_event = false

          @observer.on_leaders_death { @got_death_event = true }
          @observer.on_new_leader { @got_life_event = true }

          logger.debug { "about to observe" }

          @observer.observe!

          wait_until { !@observer.leader_alive.nil? }
        end

        it %[should be obama that won] do
          @obama.should be_leader
        end

        it %[should be palin that lost] do
          @palin.should_not be_leader
        end

        it %[should set leader_alive to true] do
          @observer.leader_alive.should be_true
        end

        it %[should fire the new leader callbacks] do
          @got_life_event.should be_true
        end
      end

      describe 'leadership transition' do
        before do
          @obama.vote!
          @palin.vote!

          wait_until { @obama.leader? }

          @palin.should_not be_leader

          @got_life_event = @got_death_event = false

          @observer.on_leaders_death { @got_death_event = true }
          @observer.on_new_leader { @got_life_event = true }

          @observer.observe!

          wait_until { !@observer.leader_alive.nil? }

          @observer.leader_alive.should be_true
          @zk.close!
          wait_until { !@zk.connected? && @palin.leader? }
        end

        it %[should be palin who is leader] do
          @palin.should be_leader
        end

        it %[should have seen both the death and life events] do
          @got_life_event.should be_true
          @got_death_event.should be_true
        end

        it %[should see the data of the new leader] do
          @observer.leader_data.should == 'palin'
        end
      end
    end
  end
end

