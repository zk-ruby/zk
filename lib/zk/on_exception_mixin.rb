module ZK
  module OnExceptionMixin
    # register a block to be called back with unhandled exceptions that occur
    # in the threadpool. 
    # 
    # @note if your exception callback block itself raises an exception, I will
    #   make fun of you.
    #
    def on_exception(&blk)
      synchronize do
        error_callbacks << blk
      end
    end

    protected
      def error_callbacks
        synchronize { @error_callbacks ||= [] }
      end

      def dispatch_to_error_handler(e)
        # make a copy that will be free from thread manipulation
        # and doesn't require holding the lock
        cbs = error_callbacks.dup

        if cbs.empty?
          default_exception_handler(e)
        else
          while cb = cbs.shift
            begin
              cb.call(e)
            rescue Exception => e
              msg = [ 
                "Exception caught in user supplied on_exception handler.", 
                "Just meditate on the irony of that for a moment. There. Good.",
                "The callback that errored was: #{cb.inspect}, the exception was",
                ""
              ]

              default_exception_handler(e, msg.join("\n"))
            end
          end
        end
      end

      def default_exception_handler(e, msg=nil)
        msg ||= 'Exception caught'
        logger.error { "#{msg}: #{e.to_std_format}" }
      end
  end
end

