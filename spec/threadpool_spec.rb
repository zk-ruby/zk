require File.join(File.dirname(__FILE__), %w[spec_helper])

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
      bad_obj = mock(:not_callable)
      bad_obj.should_not respond_to(:call)

      lambda { @threadpool.defer(bad_obj) }.should raise_error(ArgumentError)
    end

    it %[should barf if the threadpool is not running] do
      @threadpool.shutdown
      lambda { @threadpool.defer { "hai!" } }.should raise_error(ZK::Exceptions::ThreadpoolIsNotRunningException)
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
      @threadpool.start!

      @threadpool.should be_running

      @rval = nil

      @threadpool.defer { @rval = true }
      wait_until(2) { @rval }
      @rval.should be_true
    end
  end

end

