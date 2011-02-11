module ZK
  module Exceptions
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


    # these errors are returned rather than the driver level errors
    class KeeperException         < StandardError
      def self.recognized_code?(code)
        ERROR_MAP.include?(code)
      end
        
      def self.by_code(code)
        ERROR_MAP.fetch(code.to_i) { raise "API ERROR: no exception defined for code: #{code}" }
      end
    end

    class SystemError             < KeeperException; end
    class RunTimeInconsistency    < KeeperException; end
    class DataInconsistency       < KeeperException; end
    class ConnectionLoss          < KeeperException; end
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
    class SessionExpired          < KeeperException; end
    class InvalidCallback         < KeeperException; end
    class InvalidACL              < KeeperException; end
    class AuthFailed              < KeeperException; end

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
    }

    class LockFileNameParseError < KeeperException; end

    # raised when you try to vote twice in a given leader election
    class ThisIsNotChicagoError < KeeperException; end
  end
end

