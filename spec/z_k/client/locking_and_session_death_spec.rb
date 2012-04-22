shared_examples_for 'session death' do
  def deliver_session_event_to(event_num, zk)
    # jeez, Zookeeper callbacks are so frustratingly stupid
    bogus_event = ZookeeperCallbacks::WatcherCallback.new
    bogus_event.initialize_context(:type => -1, :state => event_num, :path => '', :context => 'bogustestevent')
    # XXX: this is bad because we're in the wrong thread, but we'll fix this after the next Zookeeper release
    zk.event_handler.process(bogus_event)
  end

  before do
    @other_zk = ZK.new(@connection_string)
  end

  after do
    @other_zk.close! unless @other_zk.closed?
  end

  it %[should wake up in the case of an expired session and throw an exception] do
    @a = false

    @other_zk.event_handler.register_state_handler(zoo_state) do |event|
      @a = event
    end

    th = Thread.new do
      @other_zk.block_until_node_deleted(@path)
    end

    wait_until(2) { th.status == 'sleep' }

    # not on the other thread, this may be bad
    deliver_session_event_to(zoo_state, @other_zk)

    # ditto, this is probably happening synchrnously
    wait_until(2) { @a }

    lambda { th.join(2) }.should raise_error(zoo_error_class)
  end
end # session death

shared_examples_for 'locking and session death' do
  describe 'exceptional conditions' do
    describe 'ZOO_EXPIRED_SESSION_STATE' do
      let(:zoo_state) { ZookeeperConstants::ZOO_EXPIRED_SESSION_STATE }
      let(:zoo_error_class) { ZookeeperExceptions::ZookeeperException::SessionExpired }

      it_behaves_like 'session death'
    end

    describe 'ZOO_CONNECTING_STATE' do
      let(:zoo_state) { ZookeeperConstants::ZOO_CONNECTING_STATE }
      let(:zoo_error_class) { ZookeeperExceptions::ZookeeperException::NotConnected }

      it_behaves_like 'session death'
    end

    describe 'ZOO_CLOSED_STATE' do
      let(:zoo_state) { ZookeeperConstants::ZOO_CLOSED_STATE }
      let(:zoo_error_class) { ZookeeperExceptions::ZookeeperException::ConnectionClosed }

      it_behaves_like 'session death'
    end
  end
end

describe 'threaded client and locking behavior' do
  include_context 'threaded client connection'
  it_should_behave_like 'locking and session death'
end

