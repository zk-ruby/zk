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
            # honestly, i have no idea how this could *possibly* work, but it does...
            cb_inst = new { block.call(cb_inst) }
          end
        end
      end # Callback

      module WatcherCallbackExt
        include ZookeeperConstants

        # XXX: this is not uesd it seems
        EVENT_NAME_MAP = {
          1   => 'created',
          2   => 'deleted', 
          3   => 'changed',
          4   => 'child',
          -1  => 'session',
          -2  => 'notwatching',
        }.freeze unless defined?(EVENT_NAME_MAP)

        # XXX: remove this duplication here since this is available in ZookeeperConstants
        # @private
        STATES = %w[connecting associating connected auth_failed expired_session].freeze unless defined?(STATES)

        # XXX: ditto above
        # @private
        EVENT_TYPES = %w[created deleted changed child session notwatching].freeze unless defined?(EVENT_TYPES)

        # argh, event.state_expired_session? is really dumb, should be event.expired_session?

        STATES.each do |state|
          class_eval <<-RUBY, __FILE__, __LINE__ + 1
            def #{state}?
              @state == ZOO_#{state.upcase}_STATE
            end

            alias state_#{state}? #{state}?  # alias for backwards compatibility
          RUBY
        end

        def state_name
          (name = STATE_NAMES[@state]) ? "ZOO_#{name.to_s.upcase}_STATE" : ''
        end

        EVENT_TYPES.each do |ev|
          class_eval <<-RUBY, __FILE__, __LINE__ + 1
            def node_#{ev}?
              @type == ZOO_#{ev.upcase}_EVENT
            end
          RUBY
        end

        def event_name
          (name = EVENT_TYPE_NAMES[@type]) ? "ZOO_#{name.to_s.upcase}_EVENT" : ''
        end

        alias :node_not_watching? :node_notwatching?

        # has this watcher been called because of a change in connection state?
        def state_event?
          @type == ZOO_SESSION_EVENT
        end
        alias session_event? state_event?

        # according to [the programmer's guide](http://zookeeper.apache.org/doc/r3.3.4/zookeeperProgrammers.html#Java+Binding)
        #
        # > once a ZooKeeper object is closed or receives a fatal event
        # > (SESSION_EXPIRED and AUTH_FAILED), the ZooKeeper object becomes
        # > invalid.
        # 
        # this will return true for either of those cases
        #
        def client_invalid?
          (@state == ZOO_EXPIRED_SESSION_STATE) || (@state == ZOO_AUTH_FAILED_STATE)
        end

        # has this watcher been called because of a change to a zookeeper node?
        def node_event?
          path and not path.empty?
        end
      end
    end   # Callbacks
  end # Extensions
end # ZK

# ZookeeperCallbacks::Callback.extend(ZK::Extensions::Callbacks::Callback)
ZookeeperCallbacks::Callback.send(:include, ZK::Extensions::Callbacks::Callback)
ZookeeperCallbacks::WatcherCallback.send(:include, ZK::Extensions::Callbacks::WatcherCallbackExt)

# Include the InterruptedSession module in key ZookeeperExceptions to allow
# clients to catch a single error type when waiting on a node (for example)

[:ConnectionClosed, :NotConnected, :SessionExpired, :SessionMoved, :ConnectionLoss].each do |class_name|
  ZookeeperExceptions::ZookeeperException.const_get(class_name).tap do |klass|
    klass.__send__(:include, ZK::Exceptions::InterruptedSession)
  end
end

