require 'rubygems'
require 'zk'
require 'logger'
STDOUT.sync = true
$logger = Logger.new(STDOUT)

ZK_ERRORS = [
      ZK::Exceptions::LockAssertionFailedError,
      ZK::Exceptions::InterruptedSession,
      ZK::Exceptions::Retryable,
      Zookeeper::Exceptions::ContinuationTimeoutError
    ].freeze

ZK.logger = $logger
Zookeeper.logger = $logger

def with_lock
  @zk_lock ||= @zk.locker('test_lock')
  $logger.info("Our lock: #{@zk_lock.inspect}")
  @zk_lock.lock!(true)
  @zk_lock.assert!
  yield
ensure
  if @zk_lock
    begin 
      @zk_lock.unlock!
      $logger.info("Lock successfully released.")
    rescue => ex
      $logger.warn("Failed to release lock: #{ex.inspect}")
    end
  end
end

def wait_for_lock
  $logger.info("Waiting for lock") 
  with_lock { manage }
end

def manage
  while true
    @zk_lock.assert!
    $logger.info("I have the lock")
    sleep 5
  end
end

begin
  @zk ||= ZK.new('localhost:2181')
  wait_for_lock
rescue *ZK_ERRORS => ex
  $logger.warn("Exception: #{ex}, #{ex.backtrace.first}. Retrying")
  sleep 2
  retry
end
