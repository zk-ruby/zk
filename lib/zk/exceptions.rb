module ZK
  module Exceptions
    silence_warnings do
      OK                      = 0
      # System and server-side errors
      SYSTEMERROR             = -1
      RUNTIMEINCONSISTENCY    = SYSTEMERROR - 1
      DATAINCONSISTENCY       = SYSTEMERROR - 2
      CONNECTIONLOSS          = SYSTEMERROR - 3
      MARSHALLINGERROR        = SYSTEMERROR - 4
      UNIMPLEMENTED           = SYSTEMERROR - 5
      OPERATIONTIMEOUT        = SYSTEMERROR - 6
      BADARGUMENTS            = SYSTEMERROR - 7
      # API errors  
      APIERROR                = -100; 
      NONODE                  = APIERROR - 1 # Node does not exist
      NOAUTH                  = APIERROR - 2 # Current operation not permitted
      BADVERSION              = APIERROR - 3 # Version conflict
      NOCHILDRENFOREPHEMERALS = APIERROR - 8
      NODEEXISTS              = APIERROR - 10
      NOTEMPTY                = APIERROR - 11
      SESSIONEXPIRED          = APIERROR - 12
      INVALIDCALLBACK         = APIERROR - 13
      INVALIDACL              = APIERROR - 14
      AUTHFAILED              = APIERROR - 15 # client authentication failed
    end


    # these errors are returned rather than the driver level errors
    class KeeperException         < StandardError
      def self.recognized_code?(code)
        ERROR_MAP.include?(code)
      end
        
      def self.by_code(code)
        ERROR_MAP.fetch(code.to_i) { raise "API ERROR: no exception defined for code: #{code}" }
      end
    end

    # This module is mixed into the session-related exceptions to allow
    # one to rescue that group of exceptions. It is also mixed into the related
    # ZookeeperException objects
    module InterruptedSession
    end

    # mixed into exceptions that may be retried
    module Retryable
    end

    class SystemError             < KeeperException; end
    class RunTimeInconsistency    < KeeperException; end
    class DataInconsistency       < KeeperException; end
    class MarshallingError        < KeeperException; end
    class Unimplemented           < KeeperException; end
    class BadArguments            < KeeperException; end
    class ApiError                < KeeperException; end
    class NoNode                  < KeeperException; end
    class NoAuth                  < KeeperException; end
    class BadVersion              < KeeperException; end
    class NoChildrenForEphemerals < KeeperException; end
    class NodeExists              < KeeperException; end
    class NotEmpty                < KeeperException; end
    class InvalidCallback         < KeeperException; end
    class InvalidACL              < KeeperException; end
    class AuthFailed              < KeeperException; end

    class OperationTimeOut < KeeperException
      include Retryable
    end

    class ConnectionLoss < KeeperException
      include InterruptedSession
      include Retryable
    end

    class SessionExpired < KeeperException
      include InterruptedSession
      include Retryable
    end

    # mixes in InterruptedSession, and can be raised on its own
    class InterruptedSessionException < KeeperException
      include InterruptedSession
    end

    silence_warnings do
      # @private
      ERROR_MAP = {
        SYSTEMERROR             => SystemError,
        RUNTIMEINCONSISTENCY    => RunTimeInconsistency,
        DATAINCONSISTENCY       => DataInconsistency,
        CONNECTIONLOSS          => ConnectionLoss,
        MARSHALLINGERROR        => MarshallingError,
        UNIMPLEMENTED           => Unimplemented,
        OPERATIONTIMEOUT        => OperationTimeOut,
        BADARGUMENTS            => BadArguments,
        APIERROR                => ApiError,
        NONODE                  => NoNode,
        NOAUTH                  => NoAuth,
        BADVERSION              => BadVersion,
        NOCHILDRENFOREPHEMERALS => NoChildrenForEphemerals,
        NODEEXISTS              => NodeExists,
        NOTEMPTY                => NotEmpty,
        SESSIONEXPIRED          => SessionExpired,
        INVALIDCALLBACK         => InvalidCallback,
        INVALIDACL              => InvalidACL,
        AUTHFAILED              => AuthFailed,
      }.freeze
    end

    # base class of ZK generated errors (not driver-level errors)
    class ZKError < StandardError; end

    class LockFileNameParseError < ZKError; end

    # raised when you try to vote twice in a given leader election
    class ThisIsNotChicagoError < ZKError; end
    
    # raised when close_all! has been called on a pool and some thread attempts a checkout
    class PoolIsShuttingDownException < ZKError; end

    # raised when defer is called on a threadpool that is not running
    class ThreadpoolIsNotRunningException < ZKError; end

    # raised when assert_locked_for_update! is called and no exclusive lock is held
    class MustBeExclusivelyLockedException < ZKError; end

    # raised when assert_locked_for_share! is called and no shared lock is held
    class MustBeShareLockedException < ZKError; end

    # raised for certain operations when using a chrooted connection, but the
    # root doesn't exist.
    class NonExistentRootError < ZKError; end

    # raised when someone performs a blocking ZK operation on the event dispatch thread. 
    class EventDispatchThreadException < ZKError; end

    # raised when someone calls lock.assert! but they do not hold the lock
    class LockAssertionFailedError < ZKError; end

    # called when the client is reopened, resumed, or paused when in an invalid state
    class InvalidStateError < ZKError; end

    # Raised when a NodeDeletionWatcher is interrupted by another thread
    class WakeUpException < ZKError; end

    # raised when a chrooted conection is requested but the root doesn't exist
    class ChrootPathDoesNotExistError < NoNode
      def initialize(host_string, chroot_path)
        super("Chrooted connection to #{host_string} at #{chroot_path} requested, but path did not exist")
      end
    end

    class ChrootMustStartWithASlashError < ArgumentError
      def initialize(erroneous_string)
        super("Chroot strings must start with a '/' you provided: #{erroneous_string.inspect}")
      end
    end

    # raised when we are blocked waiting on a lock and the timeout expires
    class LockWaitTimeoutError < ZKError; end
  end
end

