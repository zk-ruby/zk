$LOAD_PATH.unshift(File.expand_path('../../lib', __FILE__))

require 'zk'
require 'benchmark'

ZK_TEST_PORT = 2181

RSpec.configure do |config|
end

# method to wait until block passed returns true or timeout (default is 10 seconds) is reached 
def wait_until(timeout=10)
  time_to_stop = Time.now + timeout

  until yield 
    break if Time.now > time_to_stop
    Thread.pass
  end
end

def report_realtime(what)
  t = Benchmark.realtime { yield }
  $stderr.puts "#{what}: %0.3f" % [t.to_f]
end


