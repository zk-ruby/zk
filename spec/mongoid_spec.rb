require File.expand_path('../spec_helper', __FILE__)

describe ZK::Mongoid::Locking do
  before do
    ZK::Mongoid::Locking.zk_lock_pool = ZK.new_pool('localhost:2181', :min_clients => 1, :max_clients => 5)

    @doc        = BogusMongoid.new
    @other_doc  = BogusMongoid.new
  end

  after do
    ZK::Mongoid::Locking.zk_lock_pool.close_all!
    ZK::Mongoid::Locking.zk_lock_pool = nil
  end

  describe :lock_for_update do
    it %[should allow the same thread to re-enter the lock] do
      @counter = 0

      th = Thread.new do
        @doc.lock_for_update do
          @counter += 1

          @doc.lock_for_update do
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

      th1[:_zk_mongoid_lock_registry].should include(@doc.zk_lock_name)

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
      th2[:_zk_mongoid_lock_registry].should_not include(@other_doc.zk_lock_name)

      queue << :release_lock
      th2.join_until { @counter == 2 }
      @counter.should == 2
      @other_doc_got_lock.should be_true
    end

    describe :with_name do
      it %[should block another thread using the same name] do
        @counter = 0
        queue = Queue.new
        @other_doc_got_lock = false
        @name = 'peanuts'

        th1 = Thread.new do
          @doc.lock_for_update(@name) do
            @counter += 1
            queue.pop
          end
        end

        th1.join_until { @counter == 1 }
        @counter.should == 1

        th1[:_zk_mongoid_lock_registry].should include(@doc.zk_lock_name(@name))

        th2 = Thread.new do
          @other_doc.lock_for_update(@name) do
            @other_doc_got_lock = true
            @counter += 1
          end
        end

        th2.join(0.1)

        # this is not a deterministic check of whether or not th2 ran and did not
        # get the lock but probably close enough
        
        @counter.should == 1
        @other_doc_got_lock.should == false

        queue << :release_lock
        th2.join_until { @counter == 2 }
        @counter.should == 2
        @other_doc_got_lock.should be_true
      end

      it %[should not affect another thread using a different name] do
        @counter = 0
        queue = Queue.new
        @other_doc_got_lock = false
        @name = 'peanuts'

        th1 = Thread.new do
          @doc.lock_for_update(@name) do
            @counter += 1
            queue.pop
          end
        end

        th1.join_until { @counter == 1 }
        @counter.should == 1

        th1[:_zk_mongoid_lock_registry].should include(@doc.zk_lock_name(@name))

        th2 = Thread.new do
          @other_doc.lock_for_update do
            @other_doc_got_lock = true
            @counter += 1
          end
        end

        th2.join_until { @other_doc_got_lock }
        @other_doc_got_lock.should be_true
        
        @counter.should == 2

        queue << :release_lock
        th1.join(2).should == th1
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

end


