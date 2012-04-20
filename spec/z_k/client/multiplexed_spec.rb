require 'spec_helper'
require 'shared/client_examples'

describe 'ZK::Client::Multiplexed', :client => :multiplexed do
  before do
    @zk = ZK::Client::Multiplexed.new("localhost:#{ZK_TEST_PORT}").tap do |zk|
      wait_until { zk.connected? }
    end

    @zk.rm_rf('/test')
  end

  after do
    @zk.rm_rf('/test')
    @zk.close!

    wait_until(2) { @zk.closed? }
  end

  it_should_behave_like 'client'
end
