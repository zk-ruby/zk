module ZK
  # a more ruby-friendly wrapper around the low-level drivers
  #
  # TODO: need to implement the default watcher at this level
  #
  class Client
    def initialize(connection, opts={})
      @cnx = connection
    end

    def closed?
      raise NotImplementedError
    end

    def create(path, data='', opts={})
      # ephemeral is the default mode for us

      h = { :path => path, :data => data, :ephemeral => true, :sequence => false }.merge(opts)

      # convert between mb-style and twitter-style
      if h.delete(:ephemeral_sequential)
        h[:ephemeral] = h[:sequence] = true
      elsif h.delete(:persistent_sequential)
        h[:ephemeral] = false
        h[:sequence] = true
      elsif h.delete(:persistent)
        h[:ephemeral] = false
      end

      rv = check_rc(@cnx.create(h))
      opts[:callback] ? rv : rv[:path]
    end

    # TODO: add watch handling
    # TODO: improve callback handling
    def get(path, opts={})
      h = { :path => path }.merge(opts)

      rv = check_rc(@cnx.get(h))

      opts[:callback] ? rv : rv.values_at(:data, :stat)
    end

    # TODO: add watch handling
    def set(path, data, opts={})
      h = { :path => path, :data => data }.merge(opts)

      rv = check_rc(@cnx.set(h))

      opts[:callback] ? nil : rv[:stat]
    end


    # TODO: add watch handling
    def stat(path, opts={})
      h = { :path => path }.merge(opts)

      check_rc(@cnx.stat(h))[:stat]
    rescue Exceptions::NoNode
    end

    alias :exists? :stat

    def close!
      @cnx.close
    end

    # TODO: improve callback handling
    def delete(path, opts={})
      h = { :path => path, :version => -1 }.merge(opts)
      rv = check_rc(@cnx.delete(h))

      opts[:callback] ? nil : rv
    end

    # TODO: add watch handling
    def children(path, opts={})
      h = { :path => path }.merge(opts)
      rv = check_rc(@cnx.get_children(h))
      opts[:callback] ? nil : rv[:children]
    end

    def get_acl(path, opts={})
      h = { :path => path }.merge(opts)
      rv = check_rc(@cnx.get_acl(h))
      opts[:callback] ? nil : rv.values_at(:children, :stat)
    end

    def set_acl(path, acls, opts={})
      h = { :path => path, :acl => acls }.merge(opts)
      rv = check_rc(@cnx.set_acl(h))
      opts[:callback] ? nil : rv[:stat]
    end


    protected
      def check_rc(hash)
        hash.tap do |h|
          if code = h[:rc]
            raise Exceptions::KeeperException.by_code(code) unless code == Zookeeper::ZOK
          end
        end
      end
  end
end

