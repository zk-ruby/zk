# docs/examples/events_02.rb

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
    @queue.push(:got_event)
  end

  def run
    @zk.register(@path) do |event|
      if event.node_changed? or event.node_created?
        data = @zk.get(@path, watch: true).first    # fetch the latest data and re-set watch
        do_something_with(data)
      end
    end

    begin
      @zk.delete(@path) 
    rescue ZK::Exceptions::NoNode
    end

    @zk.stat(@path, watch: true)
    @zk.create(@path, 'Hello, events!')

    @queue.pop

    @zk.set(@path, "ooh, an update!")

    @queue.pop
  ensure
    @zk.close!
  end
end

Events.new.run

