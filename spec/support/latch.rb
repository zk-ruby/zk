# the much fabled 'latch' that tenderlove and nahi were on about

class Latch
  def initialize(count = 1)
    @count = count
    @mutex = Monitor.new
    @cond = @mutex.new_cond
  end

  def release
    @mutex.synchronize {
      @count -= 1 if @count > 0
      @cond.broadcast if @count.zero?
    }
  end

  def await
    @mutex.synchronize {
      @cond.wait_while { @count > 0 }
    }
  end
end

