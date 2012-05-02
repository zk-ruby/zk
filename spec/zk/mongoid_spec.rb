require 'spec_helper'

describe ZK::Mongoid::Locking do
  include_context 'connection opts'

  before do
    ZK::Mongoid::Locking.zk_lock_pool = ZK.new_pool(connection_host, :min_clients => 1, :max_clients => 5)

    @doc        = BogusMongoid.new
    @other_doc  = BogusMongoid.new
  end

  after do
    th = Thread.new do
      ZK::Mongoid::Locking.zk_lock_pool.close_all!
    end

    unless th.join(5) == th
      logger.warn { "Forcing pool closed!" }
      ZK::Mongoid::Locking.zk_lock_pool.force_close!
      th.join(5).should == th
    end

    ZK::Mongoid::Locking.zk_lock_pool = nil
  end

  describe :with_shared_lock do
    it %[should grab a shared lock] do
      @lock_state = nil

      th = Thread.new do
        @doc.with_shared_lock do
          @lock_state = @doc.locked_for_share?
        end
      end

      th.join_until { !@lock_state.nil? }
      @lock_state.should_not be_nil
      @lock_state.should be_true
    end

    it %[should allow another thread to enter the shared lock] do
      @counter = 0
      @queue = Queue.new

      begin
        @th1 = Thread.new do
          @doc.with_shared_lock do
            @counter += 1
            @queue.pop
          end
        end

        @th1.join_until { @counter > 0 }
        @counter.should > 0

        @th1.join_until { @queue.num_waiting > 0 }
        @queue.num_waiting.should > 0

        @th2 = Thread.new do
          @other_doc.with_shared_lock do
            @counter += 1
          end
        end

        @th2.join_until { @counter == 2 }
        @counter.should == 2

        @th2.join(2).should == @th2
      ensure
        @queue << :unlock

        unless @th1.join(2)
          $stderr.puts "UH OH! @th1 IS HUNG!!"
        end
      end
    end

    it %[should block an exclusive lock from entering] do
      begin
        q1 = Queue.new
        q2 = Queue.new

        @got_exclusive_lock = nil

        @th1 = Thread.new do
          @doc.with_shared_lock do
            q1 << :have_shared_lock
            q2.pop
            logger.debug { "@th1 releasing shared lock" }
          end
        end

        @th2 = Thread.new do
          q1.pop
          logger.debug { "@th1 has the shared lock" }

          @other_doc.lock_for_update do
            logger.debug { "@th2 got an exclusive lock" }
            @got_exclusive_lock = true
          end
        end

        @th1.join_until { q2.num_waiting >= 1 }
        q2.num_waiting.should >= 1

        @th2.join_until { q1.size == 0 }
        q1.size.should be_zero

        @got_exclusive_lock.should_not be_true

        q2.enq(:release)

        @th1.join_until { q2.size == 0 }
        q2.size.should be_zero

        @th2.join_until(5) { @got_exclusive_lock }
        @got_exclusive_lock.should be_true

      rescue Exception => e
        $stderr.puts e.to_std_format
        raise e
      ensure 
        q2 << :release

        unless @th1.join(2)
          $stderr.puts "UH OH! @th1 IS HUNG!!"
        end

        unless @th2.join(2) 
          $stderr.puts "UH OH! @th2 IS HUNG!!"
        end
      end
    end
  end

  describe :lock_for_update do
    it %[should be locked_for_update? inside the block] do
      @lock_state = nil

      th = Thread.new do
        @doc.lock_for_update do
          @lock_state = @doc.locked_for_update?
        end
      end

      th.join_until { !@lock_state.nil? }
      @lock_state.should_not be_nil
      @lock_state.should be_true
    end

    it %[should allow the same thread to re-enter the lock] do
      @counter = 0

      th = Thread.new do
        @doc.lock_for_update do
          @counter += 1
          logger.debug { "we are locked for update, trying to lock again" }

          @doc.lock_for_update do
            logger.debug { "locked again" }
            @counter += 1
          end
        end
      end

      th.join_until { @counter >= 2 }
      @counter.should == 2
    end

    it %[should block another thread from entering the lock] do
      @counter = 0
      queue = Queue.new
      @other_doc_got_lock = false

      th1 = Thread.new do
        @doc.lock_for_update do
          @counter += 1
          queue.pop
        end
      end

      th1.join_until { @counter == 1 }
      @counter.should == 1

      th1.zk_mongoid_lock_registry[:exclusive].should include(@doc.zk_lock_name)

      th2 = Thread.new do
        @other_doc.lock_for_update do
          @other_doc_got_lock = true
          @counter += 1
        end
      end

      th2.join(0.1)

      # this is not a deterministic check of whether or not th2 ran and did not
      # get the lock but probably close enough
      
      @counter.should == 1
      @other_doc_got_lock.should == false
      th2.zk_mongoid_lock_registry[:exclusive].should_not include(@other_doc.zk_lock_name)

      queue << :release_lock
      th1.join(5).should == th1

      th2.join_until { @counter == 2 }
      @counter.should == 2
      @other_doc_got_lock.should be_true
    end

    describe :with_name do
      before do
        @queue = Queue.new
      end

      after do
        if @queue.num_waiting > 0
          @queue << :bogus
          @th1.join(5).should == @th1
        end
      end

      it %[should block another thread using the same name] do
        @counter = 0
        @queue = Queue.new
        @other_doc_got_lock = false
        @name = 'peanuts'

        @th1 = Thread.new do
          @doc.lock_for_update(@name) do
            @counter += 1
            @queue.pop
          end
        end

        @th1.join_until { @counter == 1 }
        @counter.should == 1

        @th1.zk_mongoid_lock_registry[:exclusive].should include(@doc.zk_lock_name(@name))

        @th2 = Thread.new do
          @other_doc.lock_for_update(@name) do
            @other_doc_got_lock = true
            @counter += 1
          end
        end

        @th2.join(0.1)

        # this is not a deterministic check of whether or not @th2 ran and did not
        # get the lock but probably close enough
        
        @counter.should == 1
        @other_doc_got_lock.should == false

        @queue << :release_lock
        @th1.join(5).should == @th1

        @th2.join_until { @counter == 2 }
        @counter.should == 2
        @other_doc_got_lock.should be_true
      end

      it %[should not affect another thread using a different name] do
        @counter = 0
        @queue = Queue.new
        @other_doc_got_lock = false
        @name = 'peanuts'

        @th1 = Thread.new do
          @doc.lock_for_update(@name) do
            @counter += 1
            @queue.pop
          end
        end

        @th1.join_until { @counter == 1 }
        @counter.should == 1

        @th1.zk_mongoid_lock_registry[:exclusive].should include(@doc.zk_lock_name(@name))

        @th2 = Thread.new do
          @other_doc.lock_for_update do
            @other_doc_got_lock = true
            @counter += 1
          end
        end

        @th2.join_until { @other_doc_got_lock }
        @other_doc_got_lock.should be_true
        
        @counter.should == 2

        @queue << :release_lock
        @th1.join(2).should == @th1
      end
    end
  end

  describe :assert_locked_for_update! do
    it %[should raise MustBeExclusivelyLockedException if the current thread does not hold the lock] do
      lambda { @doc.assert_locked_for_update! }.should raise_error(ZK::Exceptions::MustBeExclusivelyLockedException)
    end

    it %[should not raise an exception if the current thread holds the lock] do
      lambda do
        @doc.lock_for_update do
          @doc.assert_locked_for_update!
        end
      end.should_not raise_error
    end
  end

  describe :assert_locked_for_share! do
    it %[should raise MustBeShareLockedException if the current thread does not hold a shared lock] do
      lambda { @doc.assert_locked_for_share! }.should raise_error(ZK::Exceptions::MustBeShareLockedException)
    end

    it %[should not raise an exception if the current thread holds a shared lock] do
      lambda do
        @doc.with_shared_lock do
          @doc.assert_locked_for_share!
        end
      end.should_not raise_error
    end
  end
end


