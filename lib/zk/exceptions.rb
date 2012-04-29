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

    class SystemError             < KeeperException; end
    class RunTimeInconsistency    < KeeperException; end
    class DataInconsistency       < KeeperException; end
    class MarshallingError        < KeeperException; end
    class Unimplemented           < KeeperException; end
    class OperationTimeOut        < KeeperException; end
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

    class ConnectionLoss < KeeperException
      include InterruptedSession
    end

    class SessionExpired < KeeperException
      include InterruptedSession
    end

    # mixes in InterruptedSession, and can be raised on its own
    class InterruptedSessionException < KeeperException
      include InterruptedSession
    end

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
    }.freeze unless defined?(ERROR_MAP)

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
  end
end

