module ZK
  module Locker
    # @private
    class LockOptions
      attr_reader :wait, :now, :timeout

      def initialize(opts={})
        @timeout = nil
        @now = Time.now

        raise "BLAH!" if opts.has_key?(:block)

        if opts.has_key?(:timeout)
          raise ArgumentError, ":timeout is an invalid option, use :wait with a numeric argument"
        end

        case w = opts[:wait]
        when TrueClass, FalseClass, nil
          @wait = false|w
        when Numeric
          if w < 0
            raise ArgumentError, ":wait must be a positive float or integer, or zero, not: #{w.inspect}" 
          end
          @wait = true
          @timeout = w.to_f
        else
          raise ArgumentError, ":wait must be true, false, nil, or Numeric, not #{w.inspect}" 
        end
      end

      def blocking?
        @wait
      end
    end
  end
end
