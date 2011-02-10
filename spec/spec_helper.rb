$LOAD_PATH.unshift(File.expand_path('../../lib', __FILE__))

require 'zk'

ZK_TEST_PORT = 2181

RSpec.configure do |config|
end


# method to wait until block passed returns true or timeout (default is 10 seconds) is reached 
def wait_until(timeout=10, &block)
  time_to_stop = Time.now + timeout
  until yield do 
    break if Time.now > time_to_stop
    sleep 0.3
  end
end


