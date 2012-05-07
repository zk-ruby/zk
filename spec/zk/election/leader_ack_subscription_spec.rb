require 'spec_helper'

describe ZK::Election::LeaderAckSubscription do
  include_context 'connection opts'
  let(:zk)  { ZK.new("localhost:#{ZK.test_port}", connection_opts) }

  let(:election_name) { 'student_council' }

  let(:parent) { double('parent') }

  before do
    zk.rm_rf(ZK::Election::ROOT_NODE)
  end

  it %[should] do
  end

end

