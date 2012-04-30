module ZK
  module Group
    class MembershipSubscription
      include ZK::Logging

      attr_reader :group, :opts, :callable

      def initialize(group, opts, block)
        raise ArgumentError, "block must repsond_to?(:call)" unless block.respond_to?(:call)
        @group, @opts, @callable = group, opts, block
      end

      def notify(last_members, current_members)
        # XXX: implement this in here for now, but for very large membership lists
        #      it would likely be more efficient to implement this in the caller
        if absolute_paths?
          group_path = group.path

          last_members    = last_members.map { |m| File.join(group_path, m) }
          current_members = current_members.map { |m| File.join(group_path, m) }
        end

        callable.call(last_members, current_members)
      end

      def absolute_paths?
        opts[:absolute]
      end

      def unregister
        group.unregister(self)
      end
      alias unsubscribe unregister
    end
  end
end

