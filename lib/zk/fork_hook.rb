module ZK
  module ForkHook
    include ZK::Logger
    extend self

    @mutex = Mutex.new unless defined?(@mutex)

    @hooks = {
      :prepare      => [],
      :after_child  => [],
      :after_parent => [],
    } unless defined?(@hooks)

    attr_reader :hooks, :mutex

    # @private
    def fire_prepare_hooks!
      @mutex.lock
      logger.debug { "#{__method__}" }      
      safe_call(@hooks[:prepare])
    rescue Exception => e
      @mutex.unlock rescue nil    # if something goes wrong in a hook, then release the lock
      raise e
    end

    # @private
    def fire_after_child_hooks!
      @mutex.unlock rescue nil
      logger.debug { "#{__method__}" }      
      safe_call(@hooks[:after_child])
    end

    # @private
    def fire_after_parent_hooks!
      @mutex.unlock rescue nil
      logger.debug { "#{__method__}" }      
      safe_call(@hooks[:after_parent])
    end
    
    # @private
    def clear!
      @mutex.synchronize { @hooks.values.each(&:clear) }
    end

    # @private
    def unregister(sub)
      @mutex.synchronize do
        @hooks.fetch(sub.hook_type, []).delete(sub)
      end
    end

    # do :call on each of callbacks. if a WeakRef::RefError
    # is caught, modify `callbacks` by removing the dud reference
    #
    # @private
    def safe_call(callbacks)
      cbs = callbacks.dup

      # exceptions in these hooks will be raised normally

      while cb = cbs.shift
        cb.call
      end
    end

    # @private
    def register(hook_type, block)
      unless hooks.has_key?(hook_type)
        raise "Invalid hook type specified: #{hook.inspect}" 
      end

      unless block.respond_to?(:call)
        raise ArgumentError, "You must provide either a callable an argument or a block"
      end

      ForkSubscription.new(hook_type, block).tap do |sub|
        # use a WeakRef so that the original objects can be GC'd
        @mutex.synchronize { @hooks[hook_type] << sub } 
      end
    end

    # Register a block that will be called in the parent process before a fork() occurs
    def prepare_for_fork(callable=nil, &blk)
      register(:prepare, callable || blk)
    end

    # register a block that will be called after the fork happens in the parent process
    def after_fork_in_parent(callable=nil, &blk)
      register(:after_parent, callable || blk)
    end

    # register a block that will be called after the fork happens in the child process
    def after_fork_in_child(callable=nil, &blk)
      register(:after_child, callable || blk)
    end

    def self.logger
      @logger ||= ::ZK.logger || Zookeeper::Logger::ForwardingLogger.for(::ZK::Logger.wrapped_logger, _zk_logger_name)
    end

    class ForkSubscription < Subscription::Base
      attr_reader :hook_type

      def initialize(hook_type, block)
        super(ForkHook, block)

        @hook_type = hook_type
      end
    end # ForkSubscription
  end # ForkHook

  def self.install_fork_hook
    require 'zk/install_fork_hooks'
  end

end # ZK
