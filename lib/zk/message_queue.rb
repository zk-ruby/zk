module ZK
  # implements a simple message queue based on Zookeeper recipes
  #
  # @see http://hadoop.apache.org/zookeeper/docs/r3.0.0/recipes.html#sc_recipes_Queues
  #
  # these are good for low-volume queues only
  #
  # because of the way zookeeper works, all message *titles* have to be read into memory
  # in order to see what message to process next
  #
  # @example
  #   queue = zk.queue("somequeue")
  #   queue.publish(some_string)
  #   queue.poll! # will return one message
  #   #subscribe will handle messages as they come in
  #   queue.subscribe do |title, data|
  #     #handle message
  #   end
  class MessageQueue
    # @private
    # :nodoc:
    attr_accessor :zk

    # @private
    # :nodoc:
    def initialize(zookeeper_client, queue_name, queue_root = "/_zkqueues")
      @zk = zookeeper_client
      @queue = queue_name
      @queue_root = queue_root
      @zk.create(@queue_root, "", :mode => :persistent) unless @zk.exists?(@queue_root)
      @zk.create(full_queue_path, "", :mode => :persistent) unless @zk.exists?(full_queue_path)
    end

    # publish a message to the queue, you can (optionally) use message titles
    # to guarantee unique messages in the queue
    #
    # @param [String] data any arbitrary string value
    #
    # @param [String] message_title specify a unique message title for this
    #   message (optional)
    #
    def publish(data, message_title = nil)
      mode = :persistent_sequential
      if message_title
        mode = :persistent
      else
        message_title = "message"
      end
      @zk.create("#{full_queue_path}/#{message_title}", data, :mode => mode)
    rescue ZK::Exceptions::NodeExists
      return false
    end

    # you barely ever need to actually use this method but lets you remove a
    # message from the queue by specifying its title
    #
    # @param [String] message_title the title of the message to remove
    def delete_message(message_title)
      full_path = "#{full_queue_path}/#{message_title}"
      locker = @zk.locker("#{full_queue_path}/#{message_title}")
      if locker.lock!
        begin
          @zk.delete(full_path)
          return true
        ensure
          locker.unlock!
        end
      else
        return false
      end
    end

    # grab one message from the queue
    #
    # used when you don't want to or can't subscribe
    #
    # @see ZooKeeper::MessageQueue#subscribe
    def poll!
      find_and_process_next_available(messages)
    end

    # @example
    #   # subscribe like this:
    #   subscribe {|title, data| handle_message!; true}
    #   # returning true in the block deletes the message, false unlocks and requeues
    #
    # @yield [title, data] yield to your block with the message title and the data of
    #   the message
    def subscribe(&block)
      @subscription_block = block
      @sub = @zk.register(full_queue_path) do |event, zk|
        find_and_process_next_available(@zk.children(full_queue_path, :watch => true))
      end

      find_and_process_next_available(@zk.children(full_queue_path, :watch => true))
    end

    # stop listening to this queue
    def unsubscribe
      if @sub
        @sub.unsubscribe
        @sub = nil
      end
    end

    # a list of the message titles in the queue
    def messages
      @zk.children(full_queue_path)
    end

    # highly destructive method!
    # WARNING! Will delete the queue and all messages in it
    def destroy!
      unsubscribe  # first thing, make sure we don't get any callbacks related to this
      children = @zk.children(full_queue_path)
      locks = []
      children.each do |path|
        lock = @zk.locker("#{full_queue_path}/#{path}")
        lock.lock!    # XXX(slyphon): should this be a blocking lock?
        locks << lock
      end
      children.each do |path|
        begin
          @zk.delete("#{full_queue_path}/#{path}") 
        rescue ZK::Exceptions::NoNode
        end
      end

      begin
        @zk.delete(full_queue_path) 
      rescue ZK::Exceptions::NoNode
      end

      locks.each do |lock|
        lock.unlock!
      end
    end

  private
    def find_and_process_next_available(messages)
      messages.sort! {|a,b| digit_from_path(a) <=> digit_from_path(b)}
      messages.each do |message_title|
        message_path = "#{full_queue_path}/#{message_title}"
        locker = @zk.locker(message_path)
        if locker.lock! # non-blocking lock
          begin
            data = @zk.get(message_path).first
            result = @subscription_block.call(message_title, data)
            @zk.delete(message_path) if result
          ensure
            locker.unlock!
          end
        end
      end
    end

    def full_queue_path
      @full_queue_path ||= "#{@queue_root}/#{@queue}"
    end

    def digit_from_path(path)
      path[/\d+$/].to_i
    end
  end
end
