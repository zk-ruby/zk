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

  module Extensions
    # some extensions to the ZookeeperCallbacks classes, mainly convenience
    # interrogators
    module Callbacks
      module Callback
        extend Concern

        # allow access to the connection that fired this callback
        attr_accessor :zk

        module ClassMethods
          # allows for easier construction of a user callback block that will be
          # called with the callback object itself as an argument. 
          #
          # *args, if given, will be passed on *after* the callback
          #
          # @example
          #   
          #   WatcherCallback.create do |cb|
          #     puts "watcher callback called with argument: #{cb.inspect}"
          #   end
          #
          #   "watcher callback called with argument: #<ZookeeperCallbacks::WatcherCallback:0x1018a3958 @state=3, @type=1, ...>"
          #
          #
          def create(*args, &block)
            cb_inst = new { block.call(cb_inst) }
          end
        end
      end # Callback
    end   # Callbacks
  end # Extensions
end # ZK

# ZookeeperCallbacks::Callback.extend(ZK::Extensions::Callbacks::Callback)
ZookeeperCallbacks::Callback.send(:include, ZK::Extensions::Callbacks::Callback)

# Include the InterruptedSession module in key ZookeeperExceptions to allow
# clients to catch a single error type when waiting on a node (for example)

[:ConnectionClosed, :NotConnected, :SessionExpired, :SessionMoved, :ConnectionLoss].each do |class_name|
  ZookeeperExceptions::ZookeeperException.const_get(class_name).tap do |klass|
    klass.__send__(:include, ZK::Exceptions::InterruptedSession)
  end
end

