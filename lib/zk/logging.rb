module ZK
  module Logging
    def self.included(mod)
      mod.extend(ZK::Logging::Methods)
      mod.send(:include, ZK::Logging::Methods)
    end
    
    module Methods
      def logger
        ZK.logger
      end
    end
  end
end

