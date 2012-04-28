require 'spec_helper'

describe ZK::Group::GroupBase do
  include_context 'threaded client connection'

  subject { described_class.new(@zk, group_name, :root => @base_path) }

  let(:group_name) { 'the_mothers' }
  let(:group_data) { 'of invention' }
  let(:member_names) { %w[zappa jcb collins estrada underwood] }
  
  describe :create do
    it %[should create the group with empty data] do
      subject.create
      @zk.stat(subject.path).should be_exist
    end

    it %[should create the group with specified data] do
      subject.create(group_data)
      @zk.get(subject.path).first.should == group_data
    end
  end

  describe :data do
    it %[should return the group's data] do
      @zk.mkdir_p(subject.path)
      @zk.set(subject.path, group_data)
      subject.data.should == group_data
    end
  end

  describe :data= do
    it %[should set the group's data] do
      @zk.mkdir_p(subject.path)
      subject.data = group_data
      @zk.get(subject.path).first == group_data
    end
  end

  describe :member_names do
    it %[should return a list of absolute znode paths that belong to the group] do
      member_names.each do |name|
        @zk.mkdir_p("#{subject.path}/#{name}")
      end

      subject.member_names.should == member_names.sort
    end
  end

end # ZK::Group::Base
