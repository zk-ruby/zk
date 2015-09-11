module ZK
  # use the ZK.logger if non-nil (to allow users to override the logger)
  # otherwise, use a Loggging logger based on the class name
  module Logger
    def self.wrapped_logger
      if defined?(@@wrapped_logger)
        @@wrapped_logger
      else
        @@wrapped_logger = ::Logger.new(STDERR).tap { |l| l.level = ::Logger::FATAL }
      end
    end

    def self.wrapped_logger=(log)
      @@wrapped_logger = log
    end

    # @private
    module ClassMethods
      def logger
        ::ZK.logger || Zookeeper::Logger::ForwardingLogger.for(::ZK::Logger.wrapped_logger, _zk_logger_name)
      end
    end

    def self.included(base)
      # return false if base < self    # avoid infinite recursion
      base.extend(ClassMethods)
    end

    def logger
      @logger ||= (::ZK.logger || self.class.logger)
    end
  end
end

