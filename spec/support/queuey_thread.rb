class QueueyThread < ::Thread
  attr_reader :input, :output

  def initialize(*args, &block)
    @output = Queue.new
    @input = Queue.new

    super(*args, &block)
  end
end

