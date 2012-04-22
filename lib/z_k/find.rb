module ZK
  module Find
    # like ruby's Find module, will call the given block with each _absolute_ znode path 
    # under +paths+. you can call ZK::Find.prune if you want to not recurse
    # deeper under the current directory path.
    #
    # @yield [String] each znode path under the list of paths given.
    #
    def find(zk, *paths) 
      paths.collect!{|d| d.dup}

      while p = paths.shift
        catch(:prune) do
          yield p.dup.taint
          next unless zk.exists?(p)

          zk.children(p).sort.reverse.each do |ch| 
            paths.unshift ZK.join(p, ch).untaint
          end
        end
      end
    end

    def prune
      throw :prune
    end

    module_function :find, :prune
  end
end

