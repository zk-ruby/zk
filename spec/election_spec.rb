require File.join(File.dirname(__FILE__), %w[spec_helper])

describe ZK::Election do
  before do
    @zk = ZK.new('localhost:2181')
    @zk2 = ZK.new('localhost:2181')
    @election_name = '2012'
    @data1 = 'obama'
    @data2 = 'palin'
  end

  after do
    @zk.close!
    @zk2.close!
  end

  describe 'Candidate' do
    before do
      @obama = ZK::Election::Candidate.new(@zk, @election_name, @data1)
      @palin = ZK::Election::Candidate.new(@zk2, @election_name, @data2)
    end

    describe 'vote!' do
      before do
        @obama_won = false

        @obama.on_winning_election do 
          @obama_won = true
        end

        @palin.on_winning_election do
          @palin_won = true
        end
        
        @obama.vote!
        @palin.vote!
        wait_until(2) { @obama_won }
      end

      describe 'winner' do
        it %[should fire the on_winning_election callbacks] do
          @obama_won.should be_true
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

        it %[should not fire the callbacks] do
          @palin_won.should_not be_true
        end

        it %[should take over as leader when the current leader goes away] do
          @zk.close!
          wait_until(2) { @palin_won }

          @palin_won.should be_true # god forbid
          @zk2.exists?(@palin.leader_ack_path).should be_true
          @zk2.get(@palin.leader_ack_path).first.should == @data2
        end

        it %[should remain leader if the original leader comes back] do
          @zk.close!
          wait_until(2) { @palin_won }

          zk = ZK.new('localhost:2181')
          newbama = ZK::Election::Candidate.new(zk, @election_name, @data1)

          win_again = false

          newbama.on_winning_election do
            win_again = true
          end

          newbama.vote!
          wait_until(2) { newbama.voted? }

          newbama.should be_voted
          win_again.should be_false
          newbama.should_not be_leader
        end
      end
    end
  end
end

