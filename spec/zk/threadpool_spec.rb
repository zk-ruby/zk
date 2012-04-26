require 'spec_helper'

describe ZK::Threadpool do
  before do
    @threadpool = ZK::Threadpool.new
  end

  after do
    @threadpool.shutdown
  end

  describe :new do
    it %[should be running] do
      @threadpool.should be_running
    end

    it %[should use the default size] do
      @threadpool.size.should == ZK::Threadpool.default_size
    end
  end

  describe :defer do
    it %[should run the given block on a thread in the threadpool] do
      @th = nil

      @threadpool.defer { @th = Thread.current }

      wait_until(2) { @th }

      @th.should_not == Thread.current
    end

    it %[should barf if the argument is not callable] do
      bad_obj = flexmock(:not_callable)
      bad_obj.should_not respond_to(:call)

      lambda { @threadpool.defer(bad_obj) }.should raise_error(ArgumentError)
    end

    it %[should not barf if the threadpool is not running] do
      @threadpool.shutdown
      lambda { @threadpool.defer { "hai!" } }.should_not raise_error
    end
  end

  describe :on_exception do
    it %[should register a callback that will be called if an exception is raised on the threadpool] do
      @ary = []

      @threadpool.on_exception { |exc| @ary << exc }
        
      @threadpool.defer { raise "ZOMG!" }

      wait_while(2) { @ary.empty? }

      @ary.length.should == 1

      e = @ary.shift

      e.should be_kind_of(RuntimeError)
      e.message.should == 'ZOMG!'
    end
  end

  describe :shutdown do
    it %[should set running to false] do
      @threadpool.shutdown
      @threadpool.should_not be_running
    end
  end

  describe :start! do
    it %[should be able to start a threadpool that had previously been shutdown (reuse)] do
      @threadpool.shutdown
      @threadpool.start!.should be_true

      @threadpool.should be_running

      @rval = nil

      @threadpool.defer do 
        @rval = true
      end

      wait_until(2) { @rval }
      @rval.should be_true
    end
  end

  describe :on_threadpool? do
    it %[should return true if we're currently executing on one of the threadpool threads] do
      @a = []
      @threadpool.defer { @a << @threadpool.on_threadpool? }

      wait_while(2) { @a.empty? }
      @a.should_not be_empty

      @a.first.should be_true
    end
  end
end

