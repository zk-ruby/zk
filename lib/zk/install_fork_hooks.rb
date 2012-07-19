module ::Kernel
  def fork_with_zk_hooks(&block)
    if block
      new_block = proc do
        ::ZK::ForkHook.fire_after_child_hooks!
        block.call
      end

      ::ZK::ForkHook.fire_prepare_hooks!
      fork_without_zk_hooks(&new_block).tap do
        ::ZK::ForkHook.fire_after_parent_hooks!
      end
    else
      ::ZK::ForkHook.fire_prepare_hooks!
      if pid = fork_without_zk_hooks
        ::ZK::ForkHook.fire_after_parent_hooks!
        # we're in the parent
        return pid
      else
        # we're in the child
        ::ZK::ForkHook.fire_after_child_hooks!
        return nil
      end
    end
  end

  if defined?(fork_without_zk_hooks)
    remove_method :fork
    alias fork fork_without_zk_hooks
    remove_method :fork_without_zk_hooks
  end

  alias fork_without_zk_hooks fork
  alias fork fork_with_zk_hooks
  module_function :fork
end

