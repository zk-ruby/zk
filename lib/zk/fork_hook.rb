module ZK
  module ForkHook
    include ZK::Logging

    @hooks = {
      :prepare      => [],
      :after_child  => [],
      :after_parent => [],
    } unless @hooks

    class << self
      attr_reader :hooks

      # @private
      def fire_prepare_hooks!
        safe_call(@hooks[:prepare].dup)
      end

      # @private
      def fire_after_child_hooks!
        safe_call(@hooks[:after_child].dup)
      end

      # @private
      def fire_after_parent_hooks!
        safe_call(@hooks[:after_parent].dup)
      end
      
      # @private
      def clear!
        @hooks.values(&:clear)
      end

      # @private
      def unregister(sub)
        if hook_list = @hooks[sub.hook_type]
          hook_list.delete(sub)
        end
      end

      # @private
      def safe_call(blocks)
        blocks.each do |blk|
          begin
            blk.call
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
          @hooks[hook_type] << sub
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
    end # class

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
