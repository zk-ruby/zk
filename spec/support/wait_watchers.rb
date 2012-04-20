module WaitWatchers
  class TimeoutError < StandardError; end

  # method to wait until block passed returns true or timeout (default is 10 seconds) is reached 
  # raises TiemoutError on timeout
  def wait_until(timeout=2)
    time_to_stop = Time.now + timeout
    while true
      rval = yield
      return rval if rval
      raise TimeoutError, "timeout of #{timeout}s exceeded" if Time.now > time_to_stop
      Thread.pass
    end
  end

  # inverse of wait_until
  def wait_while(timeout=2)
    time_to_stop = Time.now + timeout
    while true
      rval = yield
      return rval unless rval
      raise TimeoutError, "timeout of #{timeout}s exceeded" if Time.now > time_to_stop
      Thread.pass
    end
  end

  def report_realtime(what)
    return yield
    t = Benchmark.realtime { yield }
    $stderr.puts "#{what}: %0.3f" % [t.to_f]
  end
end


