require 'rubygems'
require 'bundler/setup'

# $LOAD_PATH.unshift(File.expand_path('../../lib', __FILE__))

Bundler.require(:development, :test)

require 'zk'
require 'zk-server'
require 'benchmark'


# Requires supporting ruby files with custom matchers and macros, etc,
# in spec/support/ and its subdirectories.
Dir[File.expand_path("../{support,shared}/**/*.rb", __FILE__)].each {|f| require f}

$stderr.sync = true

require 'flexmock'

RSpec.configure do |config|
  config.mock_with :flexmock
  config.include(FlexMock::ArgumentTypes)

  [WaitWatchers, SpecGlobalLogger, Pendings].each do |mod|
    config.include(mod)
    config.extend(mod)
  end

  if ZK.spawn_zookeeper?
    config.before(:suite) do 
      ZK.logger.debug { "Starting zookeeper service" }
      ZK::Server.run do |c|
        c.client_port = ZK.test_port
        c.force_sync  = false
        c.snap_count  = 1_000_000
      end
    end

    config.after(:suite) do
      ZK.logger.debug { "stopping zookeeper service" }
      ZK::Server.shutdown
    end
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
      break if join(0)
      Thread.pass
    end
  end
  
  def join_while(timeout=2)
    time_to_stop = Time.now + timeout

    while yield
      break if Time.now > time_to_stop
      break if join(0)
      Thread.pass
    end
  end
end


