require 'spec_helper'

# tests for the top-level module methods of ZK

describe ZK do
  describe :new do
    include_context 'connection opts'

    let(:chroot_path) { '/zktest/path/to/chroot' }

    before do
      ZK.open(*connection_args) { |z| z.rm_rf('/zktest') }
    end

    after do
      mute_logger do
        @zk.close! if @zk and not @zk.closed?
        ZK.open(*connection_args) { |z| z.rm_rf('/zktest') }
      end
    end

    describe %[with a chrooted connection string and a :chroot => '/path'] do
      it %[should raise an ArgumentError] do
        expect { @zk = ZK.new("#{connection_host}/zktest", :chroot => '/zktest') }.to raise_error(ArgumentError)
      end
    end

    describe 'with no arguments' do
      before { @zk = ZK.new }

      it %[should create a default connection] do
        expect(@zk).to be_connected
      end
    end

    describe %[with a chroot] do
      before do
        mute_logger do
          @unchroot = ZK.new(*connection_args)
        end
      end

      after do
        mute_logger do
          @unchroot.rm_rf('/zktest')
          @unchroot.close! if @unchroot and not @unchroot.closed?
        end
      end

      describe %[that doesn't exist] do
        before { @unchroot.rm_rf('/zktest') }

        describe %[with no host and a :chroot => '/path' argument] do
          before { @zk = ZK.new(:chroot => chroot_path) }

          it %[should use the default connection string, create the chroot and return the connection] do
            expect(@zk.exists?('/')).to be(true)
            @zk.create('/blah', 'data')

            expect(@unchroot.get("#{chroot_path}/blah").first).to eq('data')
          end
        end

        describe %[as a connection string] do
          describe %[and no explicit option] do
            before do
              @zk = ZK.new("#{connection_host}#{chroot_path}")    # implicit create
              wait_until { @zk.connected? }
            end

            it %[should create the chroot path and then return the connection] do
              expect(@zk.exists?('/')).to be(true)
              @zk.create('/blah', 'data')

              expect(@unchroot.get("#{chroot_path}/blah").first).to eq('data')
            end
          end

          describe %[and an explicit :chroot => :create] do
            before do
              @zk = ZK.new("#{connection_host}#{chroot_path}", :chroot => :create)
            end

            it %[should create the chroot path and then return the connection] do
              expect(@zk.exists?('/')).to be(true)
              @zk.create('/blah', 'data')

              expect(@unchroot.get("#{chroot_path}/blah").first).to eq('data')
            end
          end

          describe %[and :chroot => :check] do
            it %[should barf with a ChrootPathDoesNotExistError] do
              expect do
                # assign in case of a bug, that way this connection will get torn down
                @zk = ZK.new("#{connection_host}#{chroot_path}", :chroot => :check)
              end.to raise_error(ZK::Exceptions::ChrootPathDoesNotExistError)
            end
          end

          describe %[and :chroot => :do_nothing] do
            it %[should return a connection in a weird state] do
              @zk = ZK.new("#{connection_host}#{chroot_path}", :chroot => :do_nothing)
              expect { @zk.get('/') }.to raise_error(ZK::Exceptions::NoNode)
            end
          end

          describe %[and :chroot => '/path'] do
            before { @zk = ZK.new(connection_host, :chroot => chroot_path) }

            it %[should create the chroot path and then return the connection] do
              expect(@zk.exists?('/')).to be(true)
              @zk.create('/blah', 'data')

              expect(@unchroot.get("#{chroot_path}/blah").first).to eq('data')
            end
          end
        end # as a connection string
      end # that doesn't exist

      describe %[that exists] do
        before { @unchroot.mkdir_p(chroot_path) }

        describe %[with no host and a :chroot => '/path' argument] do
          before { @zk = ZK.new(:chroot => chroot_path) }

          it %[should use the default connection string and totally work] do
            expect(@zk.exists?('/')).to be(true)
            @zk.create('/blah', 'data')

            expect(@unchroot.get("#{chroot_path}/blah").first).to eq('data')
          end
        end

        describe %[as a connection string] do
          describe %[and no explicit option] do
            before do
              @zk = ZK.new("#{connection_host}#{chroot_path}")    # implicit create
            end

            it %[should totally work] do
              expect(@zk.exists?('/')).to be(true)
              @zk.create('/blah', 'data')

              expect(@unchroot.get("#{chroot_path}/blah").first).to eq('data')
            end
          end

          describe %[and an explicit :chroot => :create] do
            before do
              @zk = ZK.new("#{connection_host}#{chroot_path}", :chroot => :create)
            end

            it %[should totally work] do
              expect(@zk.exists?('/')).to be(true)
              @zk.create('/blah', 'data')

              expect(@unchroot.get("#{chroot_path}/blah").first).to eq('data')
            end
          end

          describe %[and :chroot => :check] do
            it %[should totally work] do
              expect do
                # assign in case of a bug, that way this connection will get torn down
                @zk = ZK.new("#{connection_host}#{chroot_path}", :chroot => :check)
              end.not_to raise_error
            end
          end

          describe %[and :chroot => :do_nothing] do
            it %[should totally work] do
              @zk = ZK.new("#{connection_host}#{chroot_path}", :chroot => :do_nothing)
              expect { @zk.get('/') }.not_to raise_error
            end
          end

          describe %[and :chroot => '/path'] do
            before { @zk = ZK.new(connection_host, :chroot => chroot_path) }

            it %[should totally work] do
              expect(@zk.exists?('/')).to be(true)
              @zk.create('/blah', 'data')

              expect(@unchroot.get("#{chroot_path}/blah").first).to eq('data')
            end
          end
        end # as a connection string
      end # that exists
    end # with a chroot
  end # :new
end # ZK

