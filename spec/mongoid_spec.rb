require File.expand_path('../spec_helper', __FILE__)

describe ZK::Mongoid::Locking do
  before do
    ZK::Mongoid::Locking.zk_lock_pool = ZK.new_pool('localhost:2181', :min_clients => 1, :max_clients => 5)

    @doc = BogusMongoid.new
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

    end

  end
end


