shared_context 'locker non-chrooted' do
  include_context 'connection opts'

  let(:zk)  { ZK.new(*connection_args) }
  let(:zk2) { ZK.new(*connection_args) }
  let(:zk3) { ZK.new(*connection_args) }

  let(:connections) { [zk, zk2, zk3] }

  let(:path) { "lock_path" }
  let(:root_lock_path) { "#{ZK::Locker.default_root_lock_node}/#{path}" }
  let(:semaphore_root_path) { "#{ZK::Locker::Semaphore.default_root_node}/#{path}" }

  before do
    wait_until{ connections.all?(&:connected?) }
    zk.rm_rf(ZK::Locker.default_root_lock_node)
    zk.rm_rf(ZK::Locker::Semaphore.default_root_node)
  end

  after do
    connections.each { |c| c.close! }
    wait_until { !connections.any?(&:connected?) }
    ZK.open(*connection_args) do |z|
      z.rm_rf(ZK::Locker.default_root_lock_node)
      z.rm_rf(ZK::Locker::Semaphore.default_root_node)
    end
  end
end

shared_context 'locker chrooted' do
  include_context 'connection opts'

  let(:chroot_path) { '/_zk_chroot_' }
  let(:path) { "lock_path" }

  let(:zk)  { ZK.new("#{connection_host}#{chroot_path}", connection_opts) }
  let(:zk2) { ZK.new("#{connection_host}#{chroot_path}", connection_opts) }
  let(:zk3) { ZK.new("#{connection_host}#{chroot_path}", connection_opts) }
  let(:connections) { [zk, zk2, zk3] }
  let(:root_lock_path) { "#{ZK::Locker.default_root_lock_node}/#{path}" }
  let(:semaphore_root_path) { "#{ZK::Locker::Semaphore.default_root_node}/#{path}" }

  before do
    ZK.open(*connection_args) do |zk|
      zk.mkdir_p(chroot_path)
    end

    wait_until{ connections.all?(&:connected?) }
  end

  after do
    connections.each { |c| c.close! }
    wait_until { !connections.any?(&:connected?) }

    ZK.open(*connection_args) do |zk|
      zk.rm_rf(chroot_path)
    end
  end
end
