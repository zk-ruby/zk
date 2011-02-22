$LOAD_PATH.unshift(File.expand_path('../../lib', __FILE__))

require 'zk'
require 'benchmark'

ZK_TEST_PORT = 2181

ZK.logger = Logger.new(File.join(ZK::ZK_ROOT, 'test.log')).tap { |log| log.level = Logger::DEBUG }

# Requires supporting ruby files with custom matchers and macros, etc,
# in spec/support/ and its subdirectories.
Dir[File.expand_path("../support/**/*.rb", __FILE__)].each {|f| require f}

RSpec.configure do |config|
end

def logger
  ZK.logger
end

# method to wait until block passed returns true or timeout (default is 2 seconds) is reached 
def wait_until(timeout=2)
  time_to_stop = Time.now + timeout

  until yield 
    break if Time.now > time_to_stop
    Thread.pass
  end
end

class ::Thread
  # join with thread until given block is true, the thread joins successfully, 
  # or timeout seconds have passed
  #
  def join_until(timeout=2)
    time_to_stop = Time.now + timeout

    until yield
      break if Time.now > time_to_stop
      break if join(0.1)
    end
  end
end

def report_realtime(what)
  t = Benchmark.realtime { yield }
  $stderr.puts "#{what}: %0.3f" % [t.to_f]
end


