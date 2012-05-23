module ZK
  TEST_LOG_PATH = File.join(ZK::ZK_ROOT, 'test.log')
end

layout = Logging.layouts.pattern(
  :pattern => '%.1l, [%d #%p] %30.30c{2}:  %m\n',
  :date_pattern => '%Y-%m-%d %H:%M:%S.%6N' 
)

appender = ENV['ZK_DEBUG'] ? Logging.appenders.stderr : Logging.appenders.file(ZK::TEST_LOG_PATH)
appender.layout = layout

%w[ZK ClientForker spec Zookeeper].each do |name|
  ::Logging.logger[name].tap do |log|
    log.appenders = [appender]
    log.level = :debug
  end
end

# this logger is kinda noisy
Logging.logger['ZK::EventHandler'].level = :info

Zookeeper.logger = Logging.logger['Zookeeper']
Zookeeper.logger.level = :warn

# Zookeeper.logger = ZK.logger.clone_new_log(:progname => 'zoo')

# Zookeeper.logger = ZK.logger
# Zookeeper.set_debug_level(4)

module SpecGlobalLogger
  def logger
    @spec_global_logger ||= ::Logging.logger['spec']
  end

  # sets the log level to FATAL for the duration of the block
  def mute_logger
    zk_log = Logging.logger['ZK']
    orig_level, zk_log.level = zk_log.level, :off
    orig_zk_level, Zookeeper.debug_level = Zookeeper.debug_level, Zookeeper::Constants::ZOO_LOG_LEVEL_ERROR
    yield
  ensure
    zk_log.level = orig_zk_level
  end
end

