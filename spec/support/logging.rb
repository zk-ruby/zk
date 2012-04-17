module ZK
  LOG_FILE = File.open(File.join(ZK::ZK_ROOT, 'test.log'), 'a').tap { |f| f.sync = true }
end

ZK.logger = Logger.new(ZK::LOG_FILE).tap { |log| log.level = Logger::DEBUG }
Zookeeper.logger = ZK.logger

ZK.logger.debug { "LOG OPEN" }

