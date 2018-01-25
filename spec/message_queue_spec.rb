require File.join(File.dirname(__FILE__), %w[spec_helper])

describe ZK::MessageQueue do
  include_context 'connection opts'

  before(:each) do
    @zk = ZK.new(connection_host)
    @zk2 = ZK.new(connection_host)
    wait_until{ @zk.connected? && @zk2.connected? }
    @queue_name = "_specQueue"
    @consume_queue = @zk.queue(@queue_name)
    @publish_queue = @zk2.queue(@queue_name)
  end

  after(:each) do
    @consume_queue.destroy!
    @zk.close!
    @zk2.close!
    wait_until{ !@zk.connected? && !@zk2.connected? }
  end

  it "should be able to receive a published message" do
    message_received = false
    @consume_queue.subscribe do |title, data|
      expect(data).to eq('mydata')
      message_received = true
    end
    @publish_queue.publish("mydata")
    wait_until {message_received }
    expect(message_received).to be(true)
  end

  it "should be able to receive a custom message title" do
    message_title = false
    @consume_queue.subscribe do |title, data|
      expect(title).to eq('title')
      message_title = true
    end
    @publish_queue.publish("data", "title")
    wait_until { message_title }
    expect(message_title).to be(true)
  end

  it "should work even after processing a message from before" do
    @publish_queue.publish("data1", "title")
    message_times = 0
    @consume_queue.subscribe do |title, data|
      expect(title).to eq("title")
      message_times += 1
    end

    @publish_queue.publish("data2", "title")
    wait_until { message_times == 2 }
    expect(message_times).to eq(2)
  end
end
