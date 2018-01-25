require 'spec_helper'

describe ZK::NodeDeletionWatcher do
  include_context 'threaded client connection'

  before do
    @path = "#{@base_path}/node_deleteion_watcher_victim"

    @n = ZK::NodeDeletionWatcher.new(@zk, @path)
    @exc = nil
  end

  describe %[when the node already exists] do
    it %[blocks the caller until the node is deleted] do
      @zk.mkdir_p(@path)

      th = Thread.new { @n.block_until_deleted }

      expect(@n.wait_until_blocked(5)).to be(true)

      logger.debug { "wait_until_blocked returned" }

      expect(@n).to be_blocked

      @zk.rm_rf(@path)

      expect(th.join(5)).to eq(th)
      expect(@n).not_to be_blocked
      expect(@n).to be_done
    end

    it %[should wake up if interrupt! is called] do
      @zk.mkdir_p(@path)

      # see _eric!! i had to do this because of 1.8.7!
      th = Thread.new do
        begin
          @n.block_until_deleted
        rescue Exception => e
          @exc = e
        end
      end

      @n.wait_until_blocked(5)

      expect(@n).to be_blocked

      @n.interrupt!
      expect(th.join(5)).to eq(th)

      expect(@exc).to be_kind_of(ZK::Exceptions::WakeUpException)
    end

    it %[should raise LockWaitTimeoutError if we time out waiting for a node to be deleted] do
      @zk.mkdir_p(@path)

      th = Thread.new do
        begin
          @n.block_until_deleted(:timeout => 0.02)
        rescue Exception => e
          @exc = e
        end
      end

      expect(@n.wait_until_blocked(5)).to be(true)

      logger.debug { "wait_until_blocked returned" }

      expect(th.join(5)).to eq(th)

      expect(@exc).to be_kind_of(ZK::Exceptions::LockWaitTimeoutError)
      expect(@n).to be_done
      expect(@n).to be_timed_out
    end
  end

  describe %[when the node doesn't exist] do
    it %[should not block the caller and be done] do
      expect(@zk.exists?(@path)).to be(false)

      th = Thread.new { @n.block_until_deleted }

      @n.wait_until_blocked
      expect(@n).not_to be_blocked
      expect(th.join(5)).to eq(th)
      expect(@n).to be_done
    end
  end

  context %[multiple nodes] do
    let(:watcher_params){ Hash.new }
    let(:paths) do
      [
        "#{@base_path}/node_deleteion_watcher_victim_one",
        "#{@base_path}/node_deleteion_watcher_victim_two",
        "#{@base_path}/node_deleteion_watcher_victim_three"
      ]
    end
    let(:created_paths){ paths }
    let(:paths_to_delete){ paths }
    let(:watcher_args) do
      args = [@zk, paths]
      args << watcher_params unless watcher_params.nil?
      args
    end
    let(:watcher){ ZK::NodeDeletionWatcher.new(*watcher_args) }
    subject{ watcher }

    before(:each) do
      created_paths.each do |path|
        @zk.mkdir_p(path)
      end
    end

    let(:watcher_block_params){ Hash.new }
    let(:watcher_wait_timeout){ 5 }

    let(:runner) do
      Thread.new do
        Thread.pass
        begin
          watcher.block_until_deleted( watcher_block_params )
        rescue Object
          @exc = $!
        end
      end
    end

    let(:controller) do
      Thread.new do
        Thread.pass
        watcher.wait_until_blocked( watcher_wait_timeout )
        paths_to_delete.each do |path|
          @zk.rm_rf(path)
        end
      end
    end

    it 'should block until all are deleted' do
      runner.run
      controller.run
      controller.join
      expect(runner.join(5)).to eq(runner)
      expect(watcher).to be_done
    end

    context %[threshold not supplied] do
      let(:watcher_params){}

      it 'should raise' do
        expect{ watcher }.to_not raise_error
      end

      describe '#threshold' do
        subject { super().threshold }
        it { should be_zero }
      end
    end

    context %[invalid threshold given] do
      let(:watcher_params){ {:threshold => :foo} }
      it 'should raise' do
        expect{ watcher }.to raise_error(ZK::Exceptions::BadArguments)
      end
    end

    context %[threshold of 1] do
      let(:watcher_params) { { :threshold => 1 } }
      context do
        let(:paths_to_delete) { paths.first(2) }
        it 'should release when 1 remains' do
          runner.run
          controller.run
          controller.join
          expect(runner.join(5)).to eq(runner)
          expect(watcher).to be_done
        end

        describe '#threshold' do
          subject { super().threshold }
          it { should == 1 }
        end
      end

      context do
        let(:paths_to_delete) { paths.first(1) }
        let(:watcher_block_params){ { :timeout => 0.02 } }
        it 'should raise when 2 remain' do
          runner.run
          controller.run
          controller.join
          expect(runner.join(5)).to eq(runner)
          expect(@exc).to be_kind_of(ZK::Exceptions::LockWaitTimeoutError)
          expect(watcher).to be_done
          expect(watcher).to be_timed_out
        end
      end
    end
  end
end
