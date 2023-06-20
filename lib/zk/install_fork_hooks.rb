module ZK
  module ForkHook
    module ModernCoreExt
      def _fork
        ::ZK::ForkHook.fire_prepare_hooks!
        pid = super
        if pid == 0
          ::ZK::ForkHook.fire_after_child_hooks!
        else
          ::ZK::ForkHook.fire_after_parent_hooks!
        end
        pid
      end
    end

    module CoreExt
      def fork(*, **)
        ::ZK::ForkHook.fire_prepare_hooks!
        if block_given?
          pid = super do
            ::ZK::ForkHook.fire_after_child_hooks!
            yield
          end
          ::ZK::ForkHook.fire_after_parent_hooks!
        else
          if pid = super
            ZK::ForkHook.fire_after_parent_hooks!
          else
            ::ZK::ForkHook.fire_after_child_hooks!
          end
        end

        pid
      end
    end

    module CoreExtPrivate
      include CoreExt
      private :fork
    end
  end
end

if Process.respond_to?(:_fork) # Ruby 3.1+
  ::Process.singleton_class.prepend(ZK::ForkHook::ModernCoreExt)
elsif Process.respond_to?(:fork)
  ::Object.prepend(ZK::ForkHook::CoreExtPrivate) if RUBY_VERSION < "3.0"
  ::Kernel.prepend(ZK::ForkHook::CoreExtPrivate)
  ::Kernel.singleton_class.prepend(ZK::ForkHook::CoreExt)
  ::Process.singleton_class.prepend(ZK::ForkHook::CoreExt)
end
