require 'spec_helper'

# more of an integration test


describe ZK::ResqueCoalesce do
  include_context 'threaded client connection'

  let(:task_name) { 'collect_underpants' }

  subject { described_class.new(@zk, task_name, :root_path => @base_path) }


  it %[should do what _eric wants] do
    uuids = []

    10.times { uuids << subject.submit }

    uuids.sort!

    uuids[0...-1].each do |uuid|
      rval = subject.maybe_run_job(uuid) { raise "NO NO! YOU FAIL!" }

      rval.should be_false
    end

    block_called = false

    subject.maybe_run_job(uuids.last) { block_called = true }

    block_called.should be_true

    uuids.each do |uuid|
      @zk.exists?(uuid).should_not be_true
    end
  end
end

