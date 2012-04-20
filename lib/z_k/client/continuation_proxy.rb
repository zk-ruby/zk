module ZK
  module Client
    # Wraps calls to zookeeper so that the requests are made asynchronously,
    # but still provides a blocking API
    #
    # @private
    class ContinuationProxy
      include ZK::Logging

      attr_accessor :zookeeper_cnx

      # @private
      def self.call_with_continuation(*syms)
        syms.each do |sym|
          class_eval(<<-EOS, __FILE__, __LINE__+1)
            def #{sym}(opts)
              logger.debug { "_call_continue(#{sym.inspect}, \#{opts.inspect})" }
              _call_continue(#{sym.inspect}, opts)
            end
          EOS
        end
      end

      call_with_continuation :create, :get, :set, :stat, :children, :delete, :get_acl, :set_acl

      def initialize(zookeeper_cnx=nil)
        @zookeeper_cnx = zookeeper_cnx
        @mutex = Mutex.new
        @dropboxen = []
      end

      # called by the multiplxed client to wake up threads that are waiting for
      # results (with an exception)
      # @private
      def connection_closed!
        _oh_noes(ZookeeperExceptions::ZookeeperException::NotConnected, 'connection closed')
      end

      # called by the multiplxed client to wake up threads that are waiting for
      # results (with an exception)
      # @private
      def expired_session!
        _oh_noes(ZookeeperExceptions::ZookeeperException::SessionExpired, 'session expired')
      end

      private
        def method_missing(m, *a, &b)
          @zookeeper_cnx.respond_to?(m) ? @zookeeper_cnx.__send__(m, *a, &b) : super
        end

        def _oh_noes(exception, message)
          @mutex.synchronize do
            @dropboxen.each do |db|
              db.oh_noes!(exception, message)
            end
          end
        end

        # not really callcc, but close enough
        # opts should be an options hash as passed through to the Zookeeper
        # layer
        def _call_continue(meth, opts)
          _assert_not_async!(meth, opts)

          opts = opts.dup

          _with_drop_box do |db|
            cb = lambda do |hash|
              logger.debug { "#{self.class}##{__method__} block pushing: #{hash.inspect}" } 
              db.push(hash)
            end

            opts[:callback] = cb

            @zookeeper_cnx.__send__(meth, opts)

            db.pop.tap do |obj|
              logger.debug { "#{self.class}##{__method__} popped and returning: #{obj.inspect}" } 
            end
          end
        end

        def _with_drop_box
          db = DropBox.current
          @mutex.synchronize { @dropboxen << db }
          yield db
        ensure
          @mutex.synchronize { @dropboxen.delete(db) }
          db.clear
        end

        def _assert_not_async!(meth, opts)
          return unless opts.has_key?(:callback)
          raise ArgumentError, "you cannot use async callbacks with a Multiplexed client! meth: #{meth.inspect}, opts: #{opts.inspect}"
        end
    end # ContinuationProxy
  end
end

