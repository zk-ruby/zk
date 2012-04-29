require 'spec_helper'

describe ZK::Group::GroupBase do
  include_context 'threaded client connection'

  before { @zk.rm_rf(@base_path) }
  after { @zk.rm_rf(@base_path) }

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

    it %[should return nil if the group is not created] do
      @zk.mkdir_p(subject.path)
      subject.create.should be_nil
    end
  end # create

  describe :create! do
    it %[should raise GroupAlreadyExistsError if the group already exists] do
      @zk.mkdir_p(subject.path)
      lambda { subject.create! }.should raise_error(ZK::Exceptions::GroupAlreadyExistsError)
    end
  end

  describe :data do
    it %[should return the group's data] do
      @zk.mkdir_p(subject.path)
      @zk.set(subject.path, group_data)
      subject.data.should == group_data
    end
  end # data

  describe :data= do
    it %[should set the group's data] do
      @zk.mkdir_p(subject.path)
      subject.data = group_data
      @zk.get(subject.path).first == group_data
    end
  end # data=

  describe :member_names do
    before do
      member_names.each do |name|
        @zk.mkdir_p("#{subject.path}/#{name}")
      end
    end

    it %[should return a list of relative znode paths that belong to the group] do
      subject.member_names.should == member_names.sort
    end

    it %[should return a list of absolute znode paths that belong to the group when :absolute => true is given] do
      subject.member_names(:absolute => true).should == member_names.sort.map {|n| "#{subject.path}/#{n}" }
    end
  end # member_names

  describe :join do
    it %[should raise GroupDoesNotExistError if the group has not been created already] do
      lambda { subject.join }.should raise_error(ZK::Exceptions::GroupDoesNotExistError)
    end

    it %[should return a Member object if the join succeeds] do
      subject.create!
      subject.join.should be_kind_of(ZK::Group::MemberBase)
    end
  end # join

end # ZK::Group::Base
