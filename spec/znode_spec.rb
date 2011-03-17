require File.expand_path('../spec_helper', __FILE__)

describe ZK::Znode do
  def cleanup!
    ZK.open(@cnx_str) do |zk|
      zk.rm_rf(@base_path)
    end
  end

  before do
    @cnx_str = 'localhost:2181'
    @base_path = '/znodetest'

    cleanup!

    @zk_pool = ZK.new(@cnx_str)
    @zk_pool.mkdir_p(@base_path)
  end

  after do
    @zk_pool.close!
    cleanup!
  end

  describe :Base do
    before do
      @path = File.join(@base_path, 'testnode')
      @orig_zk_pool, ZK::Znode::Base.zk_pool = ZK::Znode::Base.zk_pool, @zk_pool
    end

    after do
      ZK::Znode::Base.zk_pool = @orig_zk_pool
    end

    describe 'instance methods' do
      before do
        @znode = ZK::Znode::Base.new(@path)
      end

      describe 'initial state' do
        it %[should have the path] do
          @znode.path.should == @path
        end

        it %[should be a new_record?] do
          @znode.should be_new_record
        end

        it %[should not be destroyed] do
          @znode.should_not be_destroyed
        end

        it %[should be persistent by default] do
          @znode.mode.should == :persistent
        end

        it %[should not be persisted?] do
          @znode.should_not be_persisted
        end

        it %[should have dirname] do
          @znode.dirname.should == @base_path
        end

        it %[should have basename] do
          @znode.basename.should == File.basename(@path)
        end
      end

      describe 'reload' do
        before do
          @raw_data = 'this is raw data'
          @zk_pool.create(@path, @raw_data, :mode => :ephemeral)
          @znode.reload
        end

        it %[should load the data] do
          @znode.raw_data.should == @raw_data
        end

        it %[should load the stat] do
          @znode.stat.should_not be_nil
        end
      end

      describe 'delete' do
        describe 'when znode is persisted' do
          before do
            @znode.save!
            @znode.should be_persisted
            @znode.delete
          end

          it %[should delete the znode from zookeeper] do
            @zk_pool.exists?(@path).should be_false
          end

          it %[should freeze the znode] do
            @znode.should be_frozen
          end

          it %[should be destroyed] do
            @znode.should be_destroyed
          end

          it %[should not raise an error if a second delete is attempted] do
            lambda { @znode.delete }.should_not raise_error
          end
        end

        describe 'when the node has been deleted by someone else' do
          before do
            @znode.save!
            @znode.should be_persisted
            @zk_pool.delete(@path)
            lambda { @rval = @znode.delete }.should_not raise_error
          end

          it %[should return false] do
            @rval.should be_false
          end
        end
      end

      describe 'delete!' do
        describe 'when znode is persisted' do
          before do
            @znode.save!
            @znode.should be_persisted
            @znode.delete!
          end

          it %[should delete the znode from zookeeper] do
            @zk_pool.exists?(@path).should be_false
          end

          it %[should freeze the znode] do
            @znode.should be_frozen
          end

          it %[should be destroyed] do
            @znode.should be_destroyed
          end

          it %[should not raise an error if a second delete is attempted] do
            lambda { @znode.delete }.should_not raise_error
          end
        end

        describe 'when the node has been deleted by someone else' do
          before do
            @znode.save!
            @znode.should be_persisted
            @zk_pool.delete(@path)
          end

          it %[should raise ZnodeNotFound exception] do
            lambda { @znode.delete! }.should raise_error(ZK::Exceptions::ZnodeNotFound)
          end
        end
      end

      describe 'save' do
        describe 'ephemeral' do
          before do
            @znode.mode = :ephemeral
            @znode.save!
          end

          it %[should create an ephemeral node] do
            data, stat = @zk_pool.get(@znode.path)
            stat.ephemeral_owner.should_not be_zero
          end
        end
      end

      describe 'parent' do
        describe 'when not at root' do
          before do
            @znode.save!
            @parent = @znode.parent
          end

          it %[should return the parent znode object] do
            @parent.should be_kind_of(ZK::Znode::Base)
            @parent.path.should == @base_path
          end
        end

        describe 'when at root' do
          before do
            @znode = ZK::Znode::Base.new('/')
          end

          it %[should return nil for parent] do
            @znode.parent.should be_nil
          end
        end
      end
    end # instance methods

    describe 'class methods' do
      describe 'load' do
        describe %[when record doesn't exist] do
          it %[should barf with a NoNode exception] do
            lambda { ZK::Znode::Base.load(@path) }.should raise_error(ZK::Exceptions::NoNode)
          end
        end

        describe %[when node exists] do
          before do
            @raw_data = 'raw node data'
            @zk_pool.mkdir_p(@base_path)
            @zk_pool.create(@path, @raw_data)

            @znode = ZK::Znode::Base.load(@path)
          end

          it %[should not be a new_record?] do
            @znode.should_not be_new_record
          end

          it %[should be persisted?] do
            @znode.should be_persisted
          end

          it %[should have its mode set] do
            @znode.mode.should == :persistent
          end
        end
      end

      describe 'create' do
        describe %[when path doesn't exist] do
          before do
            @znode = ZK::Znode::Base.create(@path, :raw_data => '', :mode => :ephemeral)
          end

          it %[should be at version 0] do
            @znode.version.should be_zero
          end

          it %[should not be new record] do
            @znode.should_not be_new_record
          end

          it %[should be ephemeral?] do
            @znode.should be_ephemeral
          end
        end
      end
    end
  end
end


