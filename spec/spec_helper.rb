$LOAD_PATH.unshift(File.expand_path('../../lib', __FILE__))

require 'flexmock'
require 'zk'

RSpec.configure do |config|
  config.mock_with :flexmock

  config.before(:all) do
    @zk = Zookeeper.new('localhost:2181')
  end

  config.after(:all) do
    @zk.close
  end
end


# method to wait until block passed returns true or timeout (default is 10 seconds) is reached 
def wait_until(timeout=10, &block)
  time_to_stop = Time.now + timeout
  until yield do 
    break if Time.now > time_to_stop
    sleep 0.3
  end
end


