module ZK
  TEST_LOG_PATH = File.join(ZK::ZK_ROOT, 'test.log')

  def self.logging_gem_setup
    layout_opts = { 
      :pattern => '%.1l, [%d #%p] (%9.9T) %25.25c{2}:  %m\n',
    }

    layout_opts[:date_pattern] = ZK.jruby? ? '%H:%M:%S.%3N' : '%H:%M:%S.%6N'

    layout = ::Logging.layouts.pattern(layout_opts)

    appender = ENV['ZK_DEBUG'] ? ::Logging.appenders.stderr : ::Logging.appenders.file(ZK::TEST_LOG_PATH)
    appender.layout = layout
#     appender.immediate_at = "debug,info,warn,error,fatal"
#     appender.auto_flushing = true
    appender.auto_flushing = 25
    appender.flush_period = 5

    %w[ZK ClientForker spec Zookeeper].each do |name|
      ::Logging.logger[name].tap do |log|
        log.appenders = [appender]
        log.level = :debug
      end
    end

    # this logger is kinda noisy
    ::Logging.logger['ZK::EventHandler'].level = :info

    Zookeeper.logger = ::Logging.logger['Zookeeper']
    Zookeeper.logger.level = ENV['ZOOKEEPER_DEBUG'] ? :debug : :warn

    ZK::ForkHook.after_fork_in_child { ::Logging.reopen }
  end


  def self.stdlib_logger_setup
    require 'logger'
    log = ::Logger.new($stderr).tap {|l| l.level = ::Logger::DEBUG }
    ZK.logger = log
    Zookeeper.logger = log
  end
end

ZK.logging_gem_setup
# ZK.stdlib_logger_setup

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
    orig_zoo_level, Zookeeper.debug_level = Zookeeper.debug_level, Zookeeper::Constants::ZOO_LOG_LEVEL_ERROR
    yield
  ensure
    zk_log.level = orig_level
    Zookeeper.debug_level = orig_zoo_level
  end
end

