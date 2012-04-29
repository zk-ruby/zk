# docs/examples/block_until_node_deleted_ex.rb

require 'zk'

class BlockUntilNodeDeleted
  attr_reader :zk

  def initialize
    @zk = ZK.new
    @path = @zk.create('/zk-examples', sequence: true, ephemeral: true)
  end

  def block_until_node_deleted(abs_node_path)
    queue = Queue.new

    ev_sub = zk.register(abs_node_path) do |event|
      if event.node_deleted?
        queue.enq(:deleted) 
      else
        if zk.exists?(abs_node_path, :watch => true)
          # node still exists, wait for next event (better luck next time)
        else
          # ooh! surprise! it's gone!
          queue.enq(:deleted) 
        end
      end
    end
   
    # set up the callback, but bail if we don't need to wait
    return true unless zk.exists?(abs_node_path, :watch => true)  

    queue.pop # block waiting for node deletion
    true
  ensure
    ev_sub.unsubscribe
  end

  def run
    waiter = Thread.new do
      $stderr.puts "waiter thread, about to block"
      block_until_node_deleted(@path)
      $stderr.puts "waiter unblocked"
    end

    # This is not a good way to wait on another thread in general (it's
    # busy-waiting) but simple for this example.
    #
    Thread.pass until waiter.status == 'sleep'

    # we now know the other thread is waiting for deletion
    # so give 'em a thrill
    @zk.delete(@path)

    waiter.join

    $stderr.puts "hooray! success!"
  ensure
    @zk.close!
  end
end

BlockUntilNodeDeleted.new.run

