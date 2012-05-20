require 'spec_helper'

describe ZK::Election, :jruby => :broken do
  include_context 'connection opts'

  before do
    ZK.open(connection_host) do |cnx| 
      logger.debug { "REMOVING /_zkelection" }
      cnx.rm_rf('/_zkelection')
    end

    @zk = ZK.new(*connection_args)
    @zk2 = ZK.new(*connection_args)
    @election_name = '2012'
    @data1 = 'obama'
    @data2 = 'palin'
  end

  after do
    @zk.close!
    @zk2.close!

    ZK.open(connection_host) { |cnx| cnx.rm_rf('/_zkelection') }
  end

  describe 'Candidate', 'following next_node' do
    before do
      @obama = ZK::Election::Candidate.new(@zk, @election_name, :data => @data1)
      @palin = ZK::Election::Candidate.new(@zk2, @election_name, :data => @data2)
    end

    after do
      @palin.close
      @obama.close
    end

    describe 'vote!' do
      describe 'loser' do
        it %[should wait until the leader has acked before firing loser callbacks] do
          latch = Latch.new
          @do_ack = false

          @obama_won = nil
          @palin_lost = nil

          @obama_waiting = nil

          @obama.on_winning_election do
            @obama_waiting = true

            # wait for us to signal
            latch.await

#             $stderr.puts "obama on_winning_election entered"
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

          latch.release

          wait_until { @obama_won }
          @obama_won.should be_true

          lambda { oth.join(1).should == oth }.should_not raise_error

          wait_until { @palin_lost }

          @palin_lost.should be_true
        end
      end

      describe do
        before do
          Thread.abort_on_exception = true
          @obama_won = @obama_lost = @palin_won = @palin_lost = nil
          win_latch, lose_latch = Latch.new, Latch.new

          @obama.on_winning_election do 
            logger.debug { "obama on_winning_election fired" }
            @obama_won = true
            win_latch.release
          end

          @obama.on_losing_election do
            logger.debug { "obama on_losing_election fired" }
            @obama_lost = true
            lose_latch.release
          end

          @palin.on_winning_election do
            logger.debug { "palin on_winning_election fired" }
            @palin_won = true
            win_latch.release
          end

          @palin.on_losing_election do
            logger.debug { "palin on_losing_election fired" }
            @palin_lost = true
            lose_latch.release
          end
          
          @obama.vote!
          @palin.vote!

          win_latch.await
          @obama_won.should be_true

          lose_latch.await
          @palin_lost.should be_true
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
            pending_187("1.8.7's AWESOEM thread scheduler makes this test deadlock")

            @obama.zk.close!
            wait_until { @palin_won }

            @palin_won.should be_true # god forbid

            wait_until { @zk2.exists?(@palin.leader_ack_path) }

            @zk2.exists?(@palin.leader_ack_path).should be_true

            @zk2.get(@palin.leader_ack_path).first.should == @data2
          end

          it %[should remain leader if the original leader comes back] do
            pending_187("1.8.7's AWESOEM thread scheduler makes this test deadlock")
            @obama.zk.close!
            wait_until { @palin_won }

            ZK.open(*connection_args) do |zk|
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
  end

  describe :Observer do
    before do
      @zk3 = ZK.new(*connection_args)

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

          @got_life_event = @got_death_event = false

          @observer.on_leaders_death { @got_death_event = true }
          @observer.on_new_leader { @got_life_event = true }

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
          pending_187("1.8.7's AWESOEM thread scheduler makes this test deadlock")
          @obama.vote!
          wait_until { @obama.leader? }

          @palin.vote!
          @palin.should_not be_leader

          @got_life_event = @got_death_event = false

          @observer.on_leaders_death { @got_death_event = true }
          @observer.on_new_leader { @got_life_event = true }

          @observer.observe!

          wait_until { !@observer.leader_alive.nil? }

          @observer.leader_alive.should be_true
          @zk.close!
          wait_until { !@zk.connected? && @palin.leader? && @palin.leader_acked? }
        end

        it %[should be palin who is leader] do
          @palin.should be_leader
        end

        it %[should have seen both the death and life events] do
          pending 'this test is flapping'
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

