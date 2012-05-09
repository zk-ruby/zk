require 'thread'
require 'zk'

class Events
  def initialize
    @zk = ZK.new
    @queue = Queue.new
    @path = '/zk-example-events01'
  end

  def do_something_with(data)
    puts "I was told to say #{data.inspect}"
  end

  def run
    begin
      @zk.delete(@path) 
    rescue ZK::Exceptions::NoNode
    end

    @zk.register(@path) do |event|
      if event.node_changed? or event.node_created?
        # fetch the latest data
        data = @zk.get(@path).first
        do_something_with(data)
        @queue.push(:got_event)
      end
    end

    @zk.stat(@path, watch: true)
    @zk.create(@path, 'Hello, events!')

    @queue.pop
  ensure
    @zk.close!
  end
end

Events.new.run
