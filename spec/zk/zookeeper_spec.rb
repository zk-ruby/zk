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
      @zk.add_auth({:scheme => 'digest', :cert => 'bob:password'}).should include({:rc => 0})
    end
  end

  describe ZK, "with no paths" do
    it "should not exist" do
      @zk.exists?("#{@base_path}/test").should be_false
    end

    it "should create a path" do
      @zk.create("#{@base_path}/test", "test_data", :mode => :ephemeral).should == "#{@base_path}/test"
    end

    it "should be able to set the data" do
      @zk.create("#{@base_path}/test", "something", :mode => :ephemeral)
      @zk.set("#{@base_path}/test", "somethingelse")
      @zk.get("#{@base_path}/test").first.should == "somethingelse"
    end

    it "should raise an exception for a non existent path" do
      lambda { @zk.get("/non_existent_path") }.should raise_error(ZK::Exceptions::NoNode)
    end

    it "should create a path with sequence set" do
      @zk.create("#{@base_path}/test", "test_data", :mode => :persistent_sequential).should =~ /test(\d+)/
    end

    it "should create an ephemeral path" do
      @zk.create("#{@base_path}/test", "test_data", :mode => :ephemeral).should == "#{@base_path}/test"
    end

    it "should remove ephemeral path when client session ends" do
      @zk.create("#{@base_path}/test", "test_data", :mode => :ephemeral).should == "#{@base_path}/test"
      @zk.exists?("#{@base_path}/test").should_not be_nil
      @zk.close!
      wait_until(2) { !@zk.connected? }
      @zk.should_not be_connected

      @zk = ZK.new(*connection_args)
      wait_until{ @zk.connected? }
      @zk.exists?("#{@base_path}/test").should be_false
    end

    it "should remove sequential ephemeral path when client session ends" do
      created = @zk.create("#{@base_path}/test", "test_data", :mode => :ephemeral_sequential)
      created.should =~ /test(\d+)/
      @zk.exists?(created).should_not be_nil
      @zk.close!

      @zk = ZK.new(*connection_args)
      wait_until{ @zk.connected? }
      @zk.exists?(created).should be_false
    end
  end

  describe ZK, "with a path" do
    before(:each) do
      @zk.create("#{@base_path}/test", "test_data", :mode => :persistent)
    end

    it "should return a stat" do
      @zk.stat("#{@base_path}/test").should be_instance_of(Zookeeper::Stat)
    end

    it "should return a boolean" do
      @zk.exists?("#{@base_path}/test").should be_true
    end

    it "should get data and stat" do
      data, stat = @zk.get("#{@base_path}/test")
      data.should == "test_data"
      stat.should be_a_kind_of(Zookeeper::Stat)
      stat.created_time.should_not == 0
    end

    it "should set data with a file" do
      file = File.read('spec/test_file.txt')
      @zk.set("#{@base_path}/test", file)
      @zk.get("#{@base_path}/test").first.should == file
    end

    it "should delete path" do
      @zk.delete("#{@base_path}/test")
      @zk.exists?("#{@base_path}/test").should be_false
    end

    it "should create a child path" do
      @zk.create("#{@base_path}/test/child", "child", :mode => :ephemeral).should == "#{@base_path}/test/child"
    end

    it "should create sequential child paths" do
      (child1 = @zk.create("#{@base_path}/test/child", "child1", :mode => :persistent_sequential)).should =~ /\/test\/child(\d+)/
      (child2 = @zk.create("#{@base_path}/test/child", "child2", :mode => :persistent_sequential)).should =~ /\/test\/child(\d+)/
      children = @zk.children("#{@base_path}/test")
      children.length.should == 2
      children.should be_include(child1.match(/\/test\/(child\d+)/)[1])
      children.should be_include(child2.match(/\/test\/(child\d+)/)[1])
    end

    it "should have no children" do
      @zk.children("#{@base_path}/test").should be_empty
    end
  end

  describe ZK, "with children" do
    before(:each) do
      @zk.create("#{@base_path}/test", "test_data", :mode => :persistent)
      @zk.create("#{@base_path}/test/child", "child", :mode => "persistent").should == "#{@base_path}/test/child"
    end

    it "should get children" do
      @zk.children("#{@base_path}/test").should eql(["child"])
    end
  end
end

describe :threaded => true do
  include_context 'threaded client connection'
  it_should_behave_like 'ZK basic'
end


