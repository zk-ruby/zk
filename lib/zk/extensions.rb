module ZK
  # this is taken from activesupport-3.2.3, and pasted here so that we don't conflict if someone
  # is using us as part of a rails app
  #
  # i've removed the code that includes InstanceMethods (tftfy)
  # @private
  module Concern
    def self.extended(base)
      base.instance_variable_set("@_dependencies", [])
    end

    def append_features(base)
      if base.instance_variable_defined?("@_dependencies")
        base.instance_variable_get("@_dependencies") << self
        return false
      else
        return false if base < self
        @_dependencies.each { |dep| base.send(:include, dep) }
        super
        base.extend const_get("ClassMethods") if const_defined?("ClassMethods")
        base.class_eval(&@_included_block) if instance_variable_defined?("@_included_block")
      end
    end

    def included(base = nil, &block)
      if base.nil?
        @_included_block = block
      else
        super
      end
    end
  end
end # ZK

Zookeeper::Callbacks::Base.class_eval do
  # allows us to stick a reference to the connection associated with the event
  # on the event
  attr_accessor :zk
end


# Include the InterruptedSession module in key Zookeeper::Exceptions to allow
# clients to catch a single error type when waiting on a node (for example)

[:ConnectionClosed, :NotConnected, :SessionExpired, :SessionMoved, :ConnectionLoss].each do |class_name|
  Zookeeper::Exceptions.const_get(class_name).tap do |klass|
    klass.__send__(:include, ZK::Exceptions::InterruptedSession)
  end
end

[:NotConnected, :SessionExpired, :ConnectionLoss].each do |class_name|
  Zookeeper::Exceptions.const_get(class_name).tap do |klass|
    klass.__send__(:include, ZK::Exceptions::Retryable)
  end
end

