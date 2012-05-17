module ZK
  LOG_FILE = ENV['ZK_DEBUG'] ? $stderr : File.join(ZK::ZK_ROOT, 'test.log')
end

# ZK.logger = ENV['TRAVIS'] ? Logger.new($stderr) : Logger.new(ZK::LOG_FILE)

ZK.logger = Logger.new(ZK::LOG_FILE).tap do |l| 
  l.level = Logger::DEBUG
  l.progname = ' zk'
end

Zookeeper.logger.progname = 'zoo'

# Zookeeper.logger = ZK.logger.clone_new_log(:progname => 'zoo')

# Zookeeper.logger = ZK.logger
# Zookeeper.set_debug_level(4)

ZK.logger.debug { "LOG OPEN" }

module SpecGlobalLogger
  def logger
    ZK.logger
  end

  # sets the log level to FATAL for the duration of the block
  def mute_logger
    orig_level, ZK.logger.level = ZK.logger.level, Logger::FATAL
    orig_zk_level, Zookeeper.debug_level = Zookeeper.debug_level, Zookeeper::Constants::ZOO_LOG_LEVEL_ERROR
    yield
  ensure
    ZK.logger.level = orig_level
  end
end

