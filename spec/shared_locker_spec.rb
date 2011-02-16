require File.join(File.dirname(__FILE__), 'spec_helper')
require 'timeout'
require 'tracer'

if ENV['RUN_TRACER']
  $traceio = File.open('/tmp/trace.out', 'w')

  Tracer.stdout = $traceio
  Tracer.on
end

describe ZK::SharedLocker do
  if ENV['STRESS_GC']
    before do
      @orig_gc_stress, GC.stress = GC.stress, true
    end

    after do
      GC.stress = @orig_gc_stress
    end
  end

  before do
    @zk = ZK.new("localhost:#{ZK_TEST_PORT}", :watcher => :default)
    @zk2 = ZK.new("localhost:#{ZK_TEST_PORT}", :watcher => :default)
    @connections = [@zk, @zk2]

    wait_until{ @connections.all? {|c| c.connected?} }

    @path = "shlock"
    @root_lock_path = "/_zksharedlocking/#{@path}"
  end

  after do
    @connections.each { |c| c.close! }
    wait_until { @connections.all? { |c| !c.connected? } }
  end


  describe :ReadLocker do
    before do
      @read_locker  = ZK::SharedLocker.read_locker(@zk, @path)
      @read_locker2 = ZK::SharedLocker.read_locker(@zk2, @path)
    end

    describe :root_lock_path do
      it %[should be a unique namespace by default] do
        @read_locker.root_lock_path.should == @root_lock_path
      end
    end

    describe :lock! do
      describe 'non-blocking success' do
        before do
          @rval   = @read_locker.lock!
          @rval2  = @read_locker2.lock!
        end

        it %[should acquire the first lock] do
          @rval.should be_true
          @read_locker.should be_locked
        end

        it %[should acquire the second lock] do
          @rval2.should be_true
          @read_locker2.should be_locked
        end
      end

      describe 'non-blocking failure' do
        before do
          @zk.mkdir_p(@root_lock_path)
          @write_lock_path = @zk.create('/_zksharedlocking/shlock/write', '', :mode => :ephemeral_sequential)
          @rval = @read_locker.lock!
        end

        after do
          @zk.rm_rf('/_zksharedlocking')
        end

        it %[should return false] do
          @rval.should be_false
        end

        it %[should not be locked] do
          @read_locker.should_not be_locked
        end
      end

      describe 'blocking success' do
        before do
          @zk.mkdir_p(@root_lock_path)
          @write_lock_path = @zk.create('/_zksharedlocking/shlock/write', '', :mode => :ephemeral_sequential)
          $stderr.sync = true
        end

        it %[should acquire the lock after the write lock is released] do
          ary = []

          @read_locker.lock!.should be_false

          th = Thread.new do
            @read_locker.lock!(true)
            ary << :locked
          end

          ary.should be_empty
          @read_locker.should_not be_locked

          @zk.delete(@write_lock_path)

          th.join(2)

          wait_until(2) { !ary.empty? }
          ary.length.should == 1

          @read_locker.should be_locked
        end
      end
    end
  end   # ReadLocker

  describe :WriteLocker do
    before do
      @write_locker = ZK::SharedLocker.write_locker(@zk, @path)
      @write_locker2 = ZK::SharedLocker.write_locker(@zk2, @path)
    end

    describe :lock! do
      describe 'non-blocking' do
        before do
          @rval = @write_locker.lock!
          @rval2 = @write_locker2.lock!
        end

        it %[should acquire the first lock] do
          @rval.should be_true
        end

        it %[should not acquire the second lock] do
          @rval2.should be_false
        end

        it %[should acquire the second lock after the first lock is released] do
          @write_locker.unlock!.should be_true
          @write_locker2.lock!.should be_true
        end

        it %[should acquire the second lock even if a read lock is added after] do
          pending "need to mock this out, too difficult to do live"

#           @read_lock_path = @zk.create('/_zksharedlocking/shlock/read', '', :mode => :ephemeral_sequential)
#           @write_locker.unlock!.should be_true
#           @write_locker2.lock!.should be_true
        end
      end

      describe 'blocking' do
        before do
          @zk.mkdir_p(@root_lock_path)
          @read_lock_path = @zk.create('/_zksharedlocking/shlock/read', '', :mode => :ephemeral_sequential)
        end

        it %[should block waiting for the lock] do
          ary = []

          @write_locker.lock!.should be_false

          th = Thread.new do
            @write_locker.lock!(true)
            ary << :locked
          end

          Thread.pass
          ary.should be_empty
          @write_locker.should_not be_locked

          @zk.delete(@read_lock_path)

          th.join(2)

          ary.length.should == 1
          @write_locker.should be_locked
        end
      end
    end
  end
end

