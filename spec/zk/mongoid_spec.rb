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
      expect(th.join(5)).to eq(th)
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
      expect(@lock_state).not_to be_nil
      expect(@lock_state).to be(true)
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
        expect(@counter).to be > 0

        @th1.join_until { @queue.num_waiting > 0 }
        expect(@queue.num_waiting).to be > 0

        @th2 = Thread.new do
          @other_doc.with_shared_lock do
            @counter += 1
          end
        end

        @th2.join_until { @counter == 2 }
        expect(@counter).to eq(2)

        expect(@th2.join(2)).to eq(@th2)
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
        expect(q2.num_waiting).to be >= 1

        @th2.join_until { q1.size == 0 }
        expect(q1.size).to be_zero

        expect(@got_exclusive_lock).not_to be(true)

        q2.enq(:release)

        @th1.join_until { q2.size == 0 }
        expect(q2.size).to be_zero

        @th2.join_until(5) { @got_exclusive_lock }
        expect(@got_exclusive_lock).to be(true)

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
      expect(@lock_state).not_to be_nil
      expect(@lock_state).to be(true)
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
      expect(@counter).to eq(2)
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
      expect(@counter).to eq(1)

      expect(th1.zk_mongoid_lock_registry[:exclusive]).to include(@doc.zk_lock_name)

      th2 = Thread.new do
        @other_doc.lock_for_update do
          @other_doc_got_lock = true
          @counter += 1
        end
      end

      th2.join(0.1)

      # this is not a deterministic check of whether or not th2 ran and did not
      # get the lock but probably close enough

      expect(@counter).to eq(1)
      expect(@other_doc_got_lock).to eq(false)
      expect(th2.zk_mongoid_lock_registry[:exclusive]).not_to include(@other_doc.zk_lock_name)

      queue << :release_lock
      expect(th1.join(5)).to eq(th1)

      th2.join_until { @counter == 2 }
      expect(@counter).to eq(2)
      expect(@other_doc_got_lock).to be(true)
    end

    describe :with_name do
      before do
        @queue = Queue.new
      end

      after do
        if @queue.num_waiting > 0
          @queue << :bogus
          expect(@th1.join(5)).to eq(@th1)
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
        expect(@counter).to eq(1)

        expect(@th1.zk_mongoid_lock_registry[:exclusive]).to include(@doc.zk_lock_name(@name))

        @th2 = Thread.new do
          @other_doc.lock_for_update(@name) do
            @other_doc_got_lock = true
            @counter += 1
          end
        end

        @th2.join(0.1)

        # this is not a deterministic check of whether or not @th2 ran and did not
        # get the lock but probably close enough

        expect(@counter).to eq(1)
        expect(@other_doc_got_lock).to eq(false)

        @queue << :release_lock
        expect(@th1.join(5)).to eq(@th1)

        @th2.join_until { @counter == 2 }
        expect(@counter).to eq(2)
        expect(@other_doc_got_lock).to be(true)
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
        expect(@counter).to eq(1)

        expect(@th1.zk_mongoid_lock_registry[:exclusive]).to include(@doc.zk_lock_name(@name))

        @th2 = Thread.new do
          @other_doc.lock_for_update do
            @other_doc_got_lock = true
            @counter += 1
          end
        end

        @th2.join_until { @other_doc_got_lock }
        expect(@other_doc_got_lock).to be(true)

        expect(@counter).to eq(2)

        @queue << :release_lock
        expect(@th1.join(2)).to eq(@th1)
      end
    end
  end

  describe :assert_locked_for_update! do
    it %[should raise MustBeExclusivelyLockedException if the current thread does not hold the lock] do
      expect { @doc.assert_locked_for_update! }.to raise_error(ZK::Exceptions::MustBeExclusivelyLockedException)
    end

    it %[should not raise an exception if the current thread holds the lock] do
      expect do
        @doc.lock_for_update do
          @doc.assert_locked_for_update!
        end
      end.not_to raise_error
    end
  end

  describe :assert_locked_for_share! do
    it %[should raise MustBeShareLockedException if the current thread does not hold a shared lock] do
      expect { @doc.assert_locked_for_share! }.to raise_error(ZK::Exceptions::MustBeShareLockedException)
    end

    it %[should not raise an exception if the current thread holds a shared lock] do
      expect do
        @doc.with_shared_lock do
          @doc.assert_locked_for_share!
        end
      end.not_to raise_error
    end
  end
end


