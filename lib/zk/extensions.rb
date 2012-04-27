module ZK
  module Extensions
    # some extensions to the ZookeeperCallbacks classes, mainly convenience
    # interrogators
    module Callbacks
      module Callback
        # allow access to the connection that fired this callback
        attr_accessor :zk

        def self.included(mod)
          mod.extend(ZK::Extensions::Callbacks::Callback::ClassMethods)
        end

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
      end

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
        }.freeze

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

class ::Exception
  unless method_defined?(:to_std_format)
    def to_std_format
      ary = ["#{self.class}: #{message}"]
      ary.concat(backtrace || [])
      ary.join("\n\t")
    end
  end
end

class ::Thread
  def zk_mongoid_lock_registry
    self[:_zk_mongoid_lock_registry]
  end

  def zk_mongoid_lock_registry=(obj)
    self[:_zk_mongoid_lock_registry] = obj
  end
end

class ::Hash
  # taken from ActiveSupport 3.0.12, but we don't replace it if it exists
  unless method_defined?(:extractable_options?)
    def extractable_options?
      instance_of?(Hash)
    end
  end
end

class ::Array
  unless method_defined?(:extract_options!)
    def extract_options!
      if last.is_a?(Hash) && last.extractable_options?
        pop
      else
        {}
      end
    end
  end
end

