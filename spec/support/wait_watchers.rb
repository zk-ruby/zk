module WaitWatchers
  class TimeoutError < StandardError; end

  # method to wait until block passed returns truthy (false will not work) or
  # timeout (default is 2 seconds) is reached raises TiemoutError on timeout
  #
  # @returns the truthy value
  #
  # @example 
  #     
  #   @a = nil
  #
  #   th = Thread.new do
  #     sleep(1)
  #     @a = :fudge
  #   end
  #
  #   wait_until(2) { @a }.should == :fudge
  #
  def wait_until(timeout=2)
    if ZK.travis? and timeout and timeout < 5
      logger.debug { "TRAVIS: adjusting wait_until timeout from #{timeout} to 5 sec" }
      timeout = 5
    end

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
    if ZK.travis? and timeout and timeout < 5
      logger.debug { "TRAVIS: adjusting wait_while timeout from #{timeout} to 5 sec" }
      timeout = 5
    end

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

