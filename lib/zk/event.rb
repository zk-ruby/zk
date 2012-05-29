module ZK
  # Provides most of the functionality ZK uses around events. Base class is actually
  # [Zookeeper::Callbacks::WatcherCallback](http://rubydoc.info/gems/slyphon-zookeeper/Zookeeper::Callbacks/WatcherCallback),
  # but this module is mixed in and provides a lot of useful syntactic sugar.
  #
  module Event
    include Zookeeper::Constants

    # unless defined? apparently messes up yard's ability to see the @private
    silence_warnings do
      # XXX: this is not uesd it seems
      # @private
      EVENT_NAME_MAP = {
        1   => 'created',
        2   => 'deleted', 
        3   => 'changed',
        4   => 'child',
        -1  => 'session',
        -2  => 'notwatching',
      }.freeze

      # @private
      STATES = %w[connecting associating connected auth_failed expired_session].freeze
      
      # @private
      EVENT_TYPES = %w[created deleted changed child session notwatching].freeze 
    end

    # for testing, create a new Zookeeper::Callbacks::WatcherCallback and return it
    # @private
    def self.new(hash)
      Zookeeper::Callbacks::WatcherCallback.new.tap do |wc|
        wc.call(hash)
      end
    end

    # The numeric constant (one of `ZOO_*_EVENT`) that ZooKeeper sets to
    # indicate the type of event this is. Users are advised to use the '?'
    # methods below instead of using this value.
    #
    # @return [Fixnum]
    def type
      # no-op, the functionality is provided by the class this is mixed into.
      # here only for documentation purposes
    end

    # The numeric constant (one of `ZOO_*_STATE`) that ZooKeeper sets to
    # indicate the session state this event is notifying us of. Users are
    # encouraged to use the '?' methods below, instead of this value. 
    #
    # @return [Fixnum]
    def state
      # no-op, the functionality is provided by the class this is mixed into.
      # here only for documentation purposes
    end

    # The path this event is in reference to. 
    #
    # @return [String,nil] This value will be nil if `session_event?` is false, otherwise
    #   a String containing the path this event was triggered in reference to
    def path
      # no-op, the functionality is provided by the class this is mixed into.
      # here only for documentation purposes
    end

    # Is this event notifying us we're in the connecting state?
    def connecting?
      @state == ZOO_CONNECTING_STATE
    end
    alias state_connecting? connecting?

    # Is this event notifying us we're in the associating state?
    def associating?
      @state == ZOO_ASSOCIATING_STATE
    end
    alias state_associating? associating?

    # Is this event notifying us we're in the connected state?
    def connected?
      @state == ZOO_CONNECTED_STATE
    end
    alias state_connected? connected?

    # Is this event notifying us we're in the auth_failed state?
    def auth_failed?
      @state == ZOO_AUTH_FAILED_STATE
    end
    alias state_auth_failed? auth_failed?

    # Is this event notifying us we're in the expired_session state?
    def expired_session?
      @state == ZOO_EXPIRED_SESSION_STATE
    end
    alias state_expired_session? expired_session?

    # return this event's state name as a string "ZOO_*_STATE", used for debugging
    def state_name
      (name = STATE_NAMES[@state]) ? "ZOO_#{name.to_s.upcase}_STATE" : ''
    end

    # Has a node been created?
    def node_created?
      @type == ZOO_CREATED_EVENT
    end
    alias created? node_created?

    # Has a node been deleted? 
    def node_deleted?
      @type == ZOO_DELETED_EVENT
    end
    alias deleted? node_deleted?

    # Has a node changed?
    def node_changed?
      @type == ZOO_CHANGED_EVENT
    end
    alias changed? node_changed?

    # Has a node's list of children changed?
    def node_child?
      @type == ZOO_CHILD_EVENT
    end
    alias child? node_child?

    # Is this a session-related event?
    #
    # @deprecated This was an artifact of the way these methods were created
    #   originally, will be removed because it's kinda dumb. use {#session_event?}
    def node_session?
      @type == ZOO_SESSION_EVENT
    end

    # I have never seen this event delivered. here for completeness.
    def node_notwatching?
      @type == ZOO_NOTWATCHING_EVENT
    end
    alias node_not_watching? node_notwatching?

    # return this event's type name as a string "ZOO_*_EVENT", used for debugging
    def event_name
      (name = EVENT_TYPE_NAMES[@type]) ? "ZOO_#{name.to_s.upcase}_EVENT" : ''
    end

    # used by the EventHandler
    # @private
    def interest_key
      EVENT_TYPE_NAMES.fetch(@type).to_sym
    end

    # has this watcher been called because of a change in connection state?
    def session_event?
      @type == ZOO_SESSION_EVENT
    end
    alias state_event? session_event?
    alias session? session_event?
    
    # has this watcher been called because of a change to a zookeeper node?
    # `node_event?` and `session_event?` are mutually exclusive.
    def node_event?
      path and not path.empty?
    end
    alias node? node_event?

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
  end
end

# @private
Zookeeper::Callbacks::WatcherCallback.class_eval do
  include ::ZK::Event
end

