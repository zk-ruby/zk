module ZK
  TEST_LOG_PATH = File.join(ZK::ZK_ROOT, 'test.log')

  def self.setup_test_logger
    log =
      if ENV['ZK_DEBUG']
        ::Logger.new(STDERR)
      else
        ::Logger.new(TEST_LOG_PATH)
      end

    log.level = ::Logger::DEBUG

    ZK::Logger.wrapped_logger = log
  end
end

ZK.setup_test_logger

module SpecGlobalLogger
  extend self

  def logger
    @spec_global_logger ||= Zookeeper::Logger::ForwardingLogger.for(ZK::Logger.wrapped_logger, 'spec')
  end

  # sets the log level to FATAL for the duration of the block
  def mute_logger
    zk_log = ZK::Logger.wrapped_logger

    orig_level, zk_log.level = zk_log.level, ::Logger::FATAL
    yield
  ensure
    zk_log.level = orig_level
  end
end
