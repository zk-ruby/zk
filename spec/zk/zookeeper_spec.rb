require 'spec_helper'

shared_examples_for 'ZK basic' do
  before do
    logger.debug { "connection_args: #{connection_args.inspect}" }
    begin
      @zk.create(@base_path)
    rescue ZK::Exceptions::NodeExists
    end
  end

  describe ZK, "with no authentication" do
    it "should add authentication" do
      expect(@zk.add_auth({:scheme => 'digest', :cert => 'bob:password'})).to include({:rc => 0})
    end
  end

  describe ZK, "with no paths" do
    it "should not exist" do
      expect(@zk.exists?("#{@base_path}/test")).to be(false)
    end

    it "should create a path" do
      expect(@zk.create("#{@base_path}/test", "test_data", :mode => :ephemeral)).to eq("#{@base_path}/test")
    end

    it "should be able to set the data" do
      @zk.create("#{@base_path}/test", "something", :mode => :ephemeral)
      @zk.set("#{@base_path}/test", "somethingelse")
      expect(@zk.get("#{@base_path}/test").first).to eq("somethingelse")
    end

    it "should raise an exception for a non existent path" do
      expect { @zk.get("/non_existent_path") }.to raise_error(ZK::Exceptions::NoNode)
    end

    it "should create a path with sequence set" do
      expect(@zk.create("#{@base_path}/test", "test_data", :mode => :persistent_sequential)).to match(/test(\d+)/)
    end

    it "should create an ephemeral path" do
      expect(@zk.create("#{@base_path}/test", "test_data", :mode => :ephemeral)).to eq("#{@base_path}/test")
    end

    it "should remove ephemeral path when client session ends" do
      expect(@zk.create("#{@base_path}/test", "test_data", :mode => :ephemeral)).to eq("#{@base_path}/test")
      expect(@zk.exists?("#{@base_path}/test")).not_to be_nil
      @zk.close!
      wait_until(2) { !@zk.connected? }
      expect(@zk).not_to be_connected

      @zk = ZK.new(*connection_args)
      wait_until{ @zk.connected? }
      expect(@zk.exists?("#{@base_path}/test")).to be(false)
    end

    it "should remove sequential ephemeral path when client session ends" do
      created = @zk.create("#{@base_path}/test", "test_data", :mode => :ephemeral_sequential)
      expect(created).to match(/test(\d+)/)
      expect(@zk.exists?(created)).not_to be_nil
      @zk.close!

      @zk = ZK.new(*connection_args)
      wait_until{ @zk.connected? }
      expect(@zk.exists?(created)).to be(false)
    end
  end

  describe ZK, "with a path" do
    before(:each) do
      @zk.create("#{@base_path}/test", "test_data", :mode => :persistent)
    end

    it "should return a stat" do
      expect(@zk.stat("#{@base_path}/test")).to be_instance_of(Zookeeper::Stat)
    end

    it "should return a boolean" do
      expect(@zk.exists?("#{@base_path}/test")).to be(true)
    end

    it "should get data and stat" do
      data, stat = @zk.get("#{@base_path}/test")
      expect(data).to eq("test_data")
      expect(stat).to be_a_kind_of(Zookeeper::Stat)
      expect(stat.created_time).not_to eq(0)
    end

    it "should set data with a file" do
      file = File.read('spec/test_file.txt')
      @zk.set("#{@base_path}/test", file)
      expect(@zk.get("#{@base_path}/test").first).to eq(file)
    end

    it "should delete path" do
      @zk.delete("#{@base_path}/test")
      expect(@zk.exists?("#{@base_path}/test")).to be(false)
    end

    it "should create a child path" do
      expect(@zk.create("#{@base_path}/test/child", "child", :mode => :ephemeral)).to eq("#{@base_path}/test/child")
    end

    it "should create sequential child paths" do
      expect(child1 = @zk.create("#{@base_path}/test/child", "child1", :mode => :persistent_sequential)).to match(/\/test\/child(\d+)/)
      expect(child2 = @zk.create("#{@base_path}/test/child", "child2", :mode => :persistent_sequential)).to match(/\/test\/child(\d+)/)
      children = @zk.children("#{@base_path}/test")
      expect(children.length).to eq(2)
      expect(children).to be_include(child1.match(/\/test\/(child\d+)/)[1])
      expect(children).to be_include(child2.match(/\/test\/(child\d+)/)[1])
    end

    it "should have no children" do
      expect(@zk.children("#{@base_path}/test")).to be_empty
    end
  end

  describe ZK, "with children" do
    before(:each) do
      @zk.create("#{@base_path}/test", "test_data", :mode => :persistent)
      expect(@zk.create("#{@base_path}/test/child", "child", :mode => "persistent")).to eq("#{@base_path}/test/child")
    end

    it "should get children" do
      expect(@zk.children("#{@base_path}/test")).to eql(["child"])
    end
  end
end

describe :threaded => true do
  include_context 'threaded client connection'
  it_should_behave_like 'ZK basic'
end


