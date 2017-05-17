require 'spec_helper'

describe 'forked client integration' do
  describe :forked, :fork_required => true, :rbx => :broken do
    include_context 'connection opts'

    before do
      @base_path = '/zktests'
      @pids_root = "#{@base_path}/pid"
      
      @cnx_args = ["#{ZK.default_host}:#{ZK.test_port}", { :thread => :per_callback, :timeout => 5 }]

      ZK.open(*@cnx_args) do |z|
        z.rm_rf(@base_path)
        z.mkdir_p(@pids_root)
      end
    end

    after do
      ZK.open(*connection_args) { |z| z.rm_rf(@base_path) }
    end

    it %[should deliver callbacks in the child] do
      10.times do 
        ClientForker.run(@cnx_args, @base_path) do |forker|
          expect(forker.stat).not_to be_signaled
          expect(forker.stat).to be_exited
          expect(forker.stat).to be_success
        end
      end
    end # should deliver callbacks in the child
  end # forked
end

