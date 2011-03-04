require File.join(File.dirname(__FILE__), %w[spec_helper])

describe ZK do
  before do
    @cnx_str = "localhost:#{ZK_TEST_PORT}"
    @zk = ZK.new(@cnx_str)

    @path = "/_testWatch"
    wait_until { @zk.connected? }
  end

  after do
    @zk.close!
    wait_until { !@zk.connected? }

    ZK.open(@cnx_str) { |zk| zk.rm_rf(@path) }
  end

  it "should call back to path registers" do
    locker = Mutex.new
    callback_called = false

    @zk.watcher.register(@path) do |event|
      locker.synchronize do
        callback_called = true
      end
      event.path.should == @path
    end

    @zk.exists?(@path, :watch => true).should be_false
    @zk.create(@path, "", :mode => :ephemeral)

    wait_until(5) { locker.synchronize { callback_called } }
    callback_called.should be_true
  end

  it %[should only deliver an event once to each watcher registered for exists?] do
    events = []

    sub = @zk.watcher.register(@path) do |ev|
      logger.debug "got event #{ev}"
      events << ev
    end

    2.times do
      @zk.exists?(@path, :watch => true).should_not be_true
    end

    @zk.create(@path, '', :mode => :ephemeral)

    wait_until { events.length >= 2 }
    events.length.should == 1
  end

  it %[should only deliver an event once to each watcher registered for get] do
    events = []

    @zk.create(@path, 'one', :mode => :ephemeral)

    sub = @zk.watcher.register(@path) do |ev|
      logger.debug "got event #{ev}"
      events << ev
    end

    2.times do
      data, stat = @zk.get(@path, :watch => true)
      data.should == 'one'
    end

    @zk.set(@path, 'two')

    wait_until { events.length >= 2 }
    events.length.should == 1
  end


  it %[should only deliver an event once to each watcher registered for children] do
    events = []

    @zk.create(@path, '')

    sub = @zk.watcher.register(@path) do |ev|
      logger.debug "got event #{ev}"
      events << ev
    end

    2.times do
      children = @zk.children(@path, :watch => true)
      children.should be_empty
    end

    @zk.create("#{@path}/pfx", '', :mode => :ephemeral_sequential)

    wait_until { events.length >= 2 }
    events.length.should == 1
  end

  describe :event_types do
    lambda do
      @events, @subs = Hash.new {|h,k| h[k] = []}, []

      @event_names = [:create, :delete, :change, :children]

      @event_names.each do |ev_name|
        @zk.on(@path, ev_name) do |ev|
          @events[ev_name] << ev
        end
      end

      @zk.exists?(@path, :watch => true)

      @zk.create(@path, '', :mode => :persistent)
      @zk.create("#{@path}/child", '', :mode => :ephemeral)
      @zk.set(@path, 'changed')
      @zk.rm_rf(@path)

      wait_until!(5) do
        @event_names.all? { |ev_name| !@events[ev_name].empty? }
      end
    end

    
    describe :deleted do
      before do
        @event = nil

        @zk.create(@path, '', :mode => :ephemeral)

        @zk.on(@path, :deleted) do |ev|
          @event = ev
        end

        @zk.exists?(@path, :watch => true).should be_true
      end
    end
   

  end
end
