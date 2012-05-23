module ZK
  # use the ZK.logger if non-nil (to allow users to override the logger)
  # otherwise, use a Loggging logger based on the class name
  module Logging
    extend ZK::Concern

    included do
      def self.logger
        ::ZK.logger || ::Logging.logger[logger_name]
      end
    end

    def self.set_default
      ::Logging.logger['ZK'].tap do |ch_root|
        ::Logging.appenders.stderr.tap do |serr|
          serr.layout = ::Logging.layouts.pattern(
            :pattern => '%.1l, [%d #p] %c30.30{2}:  %m\n',
            :date_pattern => '%Y-%m-%d %H:%M:%S.%6N' 
          )

          serr.auto_flushing = 25
          serr.flush_period = 5

          ch_root.add_appenders(serr)
        end

        ch_root.level = ENV['ZK_DEBUG'] ? :debug : :off
      end
    end

    def logger
      self.class.logger
    end
  end
end

