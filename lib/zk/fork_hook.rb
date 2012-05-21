module ZK
  module ForkHook
    include ZK::Logging
    extend self

    @mutex = Mutex.new unless @mutex

    @hooks = {
      :prepare      => [],
      :after_child  => [],
      :after_parent => [],
    } unless @hooks

    attr_reader :hooks, :mutex

    # @private
    def fire_prepare_hooks!
      @mutex.lock
      safe_call(@hooks[:prepare])
    end

    # @private
    def fire_after_child_hooks!
      safe_call(@hooks[:after_child])
    ensure
      @mutex.unlock rescue nil
    end

    # @private
    def fire_after_parent_hooks!
      safe_call(@hooks[:after_parent])
    ensure
      @mutex.unlock rescue nil
    end
    
    # @private
    def clear!
      @mutex.synchronize { @hooks.values(&:clear) }
    end

    # @private
    def unregister(sub)
      @mutex.synchronize do
        @hooks.fetch(sub.hook_type, []).delete(sub)
      end
    end

    # @private
    def safe_call(callbacks)
      cbs = callbacks.dup

      while cb = cbs.shift
        begin
          cb.call
        rescue WeakRef::RefError
          # clean weakrefs out of the original callback arrays if they're bad
          callbacks.delete(cb)
        rescue Exception => e
          logger.error { e.to_std_format }
        end
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
        @mutex.synchronize { @hooks[hook_type] << WeakRef.new(sub) } 
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
