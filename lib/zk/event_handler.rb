module ZK
  # This is the default watcher provided by the zookeeper connection
  # watchers are implemented by adding the :watch => true flag to
  # any #children or #get or #exists calls
  #
  # you never really need to initialize this yourself
  class EventHandler
    include Java::OrgApacheZookeeper::Watcher if defined?(JRUBY_VERSION)
    include ZK::Logger

    # @private
    VALID_WATCH_TYPES = [:data, :child].freeze

    # @private
    ALL_NODE_EVENTS_KEY = :all_node_events

    # @private
    ALL_STATE_EVENTS_KEY = :all_state_events

    # @private
    VALID_THREAD_OPTS = [:single, :per_callback].freeze

    # @private
    attr_accessor :zk

    # @private
    # :nodoc:
    def initialize(zookeeper_client, opts={})
      @zk = zookeeper_client

      @orig_pid = Process.pid

      @thread_opt = opts.fetch(:thread, :single)
      EventHandlerSubscription.class_for_thread_option(@thread_opt) # this is side-effecty, will raise an ArgumentError if given a bad value. 

      @mutex = nil
      @setup_watcher_mutex = nil

      @callbacks = Hash.new { |h,k| h[k] = [] }

      @outstanding_watches = VALID_WATCH_TYPES.inject({}) do |h,k|
        h.tap { |x| x[k] = Set.new }
      end

      @state = :running

      reopen_after_fork!
    end
   
    # do not call this method. it is inteded for use only when we've forked and 
    # all other threads are dead.
    #
    # @private
    def reopen_after_fork!
#       logger.debug { "#{self.class}##{__method__}" }
      @mutex = Monitor.new
      @setup_watcher_mutex = Monitor.new

      # XXX: need to test this w/ actor-style callbacks
      
      @state = :running
      @callbacks.values.flatten.each { |cb| cb.reopen_after_fork! if cb.respond_to?(:reopen_after_fork!) }
      @outstanding_watches.values.each { |set| set.clear }
      nil
    end

    # @see ZK::Client::Base#register
    def register(path, opts={}, &block)
      path = ALL_NODE_EVENTS_KEY if path == :all

      hash = {:thread => @thread_opt}

      # gah, ok, handle the 1.0 form
      case opts
      when Array, Symbol
        warn "Deprecated! #{self.class}#register use the :only option instead of passing a symbol or array"
        hash[:only] = opts
      when Hash
        hash.merge!(opts)
      when nil
        # no-op
      else
        raise ArgumentError, "don't know how to handle options: #{opts.inspect}" 
      end

      EventHandlerSubscription.new(self, path, block, hash).tap do |subscription|
        synchronize { @callbacks[path] << subscription }
      end
    end
    alias :subscribe :register

    # Registers a "state of the connection" handler
    #
    # Valid states are: connecting, associating, connected, auth_failed,
    # expired_session. Of all of these, you are probably most likely
    # interested in `expired_session` and `connecting`, which are fired
    # when you either lose your session (and have to completely reconnect),
    # or when there's a temporary loss in connection and Zookeeper recommends
    # you go into 'safe mode'.
    #
    # Note that these callbacks are *not* one-shot like the path callbacks,
    # these will be called back with every relative state event, there is 
    # no need to re-register
    #
    # @param [String,:all] state The state you want to register for or :all
    #   to be called back with every state change
    #
    # @param [Block] block the block to execute on state changes
    # @yield [event] yields your block with
    #
    def register_state_handler(state, &block)
      register(state_key(state), &block)
    end

    # @deprecated use #unsubscribe on the subscription object
    # @see ZK::EventHandlerSubscription#unsubscribe
    def unregister_state_handler(*args)
      if args.first.is_a?(EventHandlerSubscription::Base)
        unregister(args.first)
      else
        unregister(state_key(args.first), args[1])
      end
    end

    # @deprecated use #unsubscribe on the subscription object
    # @see ZK::EventHandlerSubscription#unsubscribe
    def unregister(*args)
      if args.first.is_a?(EventHandlerSubscription::Base)
        subscription = args.first
      elsif args.first.is_a?(String) and args[1].is_a?(EventHandlerSubscription::Base)
        subscription = args[1]
      else
        path, index = args[0..1]
        synchronize { @callbacks[path][index] = nil }
        return
      end

      synchronize do
        ary = @callbacks[subscription.path]

        idx = ary.index(subscription) and ary.delete_at(idx)
        @callbacks.delete(subscription.path) if ary.empty?
      end

      nil
    end
    alias :unsubscribe :unregister

    # called from the Client registered callback when an event fires
    #
    # @note this is *ONLY* dealing with asynchronous callbacks! watchers
    #   and session events go through here, NOT anything else!!
    #
    # @private
    def process(event, watch_type = nil)
      @zk.raw_event_handler(event)

      logger.debug { "EventHandler#process dispatching event for #{watch_type.inspect}: #{event.inspect}" }# unless event.type == -1
      event.zk = @zk

      cb_keys = 
        if event.node_event?
          [event.path, ALL_NODE_EVENTS_KEY]
        elsif event.session_event?
          [state_key(event.state), ALL_STATE_EVENTS_KEY]
        else
          raise ZKError, "don't know how to process event: #{event.inspect}"
        end

      cb_ary = synchronize do 
        clear_watch_restrictions(event, watch_type)

        @callbacks.values_at(*cb_keys)
      end

      cb_ary.flatten! # takes care of not modifying original arrays
      cb_ary.compact!

      # we only filter for node events
      if event.node_event?
        interest_key = event.interest_key
        cb_ary.select! { |sub| sub.interests.include?(interest_key) }
      end

      safe_call(cb_ary, event)
    end

    # happens inside the lock, clears the restriction on setting new watches
    # for a given path/event type combination
    #
    def clear_watch_restrictions(event, watch_type)
      return unless event.node_event?

      if watch_type
        logger.debug { "re-allowing #{watch_type.inspect} watches on path #{event.path.inspect}" }
        
        # we recieved a watch event for this path, now we allow code to set new watchers
        @outstanding_watches[watch_type].delete(event.path)
      end
    end
    private :clear_watch_restrictions

    # used during shutdown to clear registered listeners
    # @private
    def clear! #:nodoc:
      synchronize do
        @callbacks.clear
        nil
      end
    end 

    # used when establishing a new session
    def clear_outstanding_watch_restrictions!
      synchronize do
        @outstanding_watches.values.each { |set| set.clear }
      end
    end

    # shut down the EventHandlerSubscriptions 
    def close
      synchronize do
        @callbacks.values.flatten.each(&:close)
        @state = :closed
        clear!
      end
    end

    # @private
    def pause_before_fork_in_parent
      synchronize do
        raise InvalidStateError, "invalid state, expected to be :running, was #{@state.inspect}" if @state != :running
        return false if @state == :paused
        @state = :paused
      end
      logger.debug { "#{self.class}##{__method__}" }

      @callbacks.values.flatten.each(&:pause_before_fork_in_parent)
    end

    # @private
    def resume_after_fork_in_parent
      synchronize do
        raise InvalidStateError, "expected :paused, was #{@state.inspect}" if @state != :paused
        @state = :running
      end
      logger.debug { "#{self.class}##{__method__}" }

      @callbacks.values.flatten.each(&:resume_after_fork_in_parent)
    end

    # @private
    def get_default_watcher_block
      @default_watcher_block ||= lambda do |hash|
        watcher_callback.tap do |cb|
          cb.call(hash)
        end
      end
    end

    # returns true if there's a pending watch of type for path
    # @private
    def restricting_new_watches_for?(watch_type, path)
      synchronize do
        if set = @outstanding_watches[watch_type]
          return set.include?(path)
        end
      end

      false
    end

    # implements not only setting up the watcher callback, but deduplicating 
    # event delivery. Keeps track of in-flight watcher-type+path requests and
    # doesn't re-register the watcher with the server until a response has been
    # fired. This prevents one event delivery to *every* callback per :watch => true
    # argument.
    #
    # due to arguably poor design, we destructively modify opts before we yield
    # and the client implictly knows this (this method constitutes some of the option
    # parsing for the base class methods)
    #
    # @private
    def setup_watcher!(watch_type, opts)
      return yield unless opts.delete(:watch)

      @setup_watcher_mutex.synchronize do
        path = opts[:path]
        added, set = nil, nil

        synchronize do
          set = @outstanding_watches.fetch(watch_type)
          added = set.add?(path)
        end

        if added
          logger.debug { "adding watcher #{watch_type.inspect} for #{path.inspect}"}

          # if we added the path to the set, blocking further registration of
          # watches and an exception is raised then we rollback
          begin
            # this path has no outstanding watchers, let it do its thing
            opts[:watcher] = watcher_callback(watch_type)

            yield opts
          rescue Exception
            synchronize do
              set.delete(path)
            end
            raise
          end
        else
          logger.debug { "watcher #{watch_type.inspect} already set for #{path.inspect}"}

          # we did not add the path to the set, which means we are not
          # responsible for removing a block on further adds if the operation
          # fails, therefore, we just yield
          yield opts
        end
      end
    end

    private
      def synchronize
        @mutex.synchronize { yield }
      end

      def watcher_callback(watch_type = nil)
        Zookeeper::Callbacks::WatcherCallback.create { |event| process(event, watch_type) }
      end

      def state_key(arg)
        int = 
          case arg
          when :all
            # XXX: this is a nasty side-exit
            return ALL_STATE_EVENTS_KEY
          when String, Symbol
            Zookeeper::Constants.const_get(:"ZOO_#{arg.to_s.upcase}_STATE")
          when Integer
            arg
          else
            raise NameError, "unrecognized state: #{arg.inspect}" # ugh lame
          end

        "state_#{int}"
      rescue NameError
        raise ArgumentError, "#{arg} is not a valid zookeeper state", caller
      end

      def safe_call(callbacks, *args)
        callbacks.each do |cb|
          next unless cb.respond_to?(:call)

          if cb.async?
            cb.call(*args)
          else
            zk.defer do 
              logger.debug { "called #{cb.inspect} with #{args.inspect} on threadpool" }
              cb.call(*args)
            end
          end
        end
      end
  end # EventHandler
end # ZK 

