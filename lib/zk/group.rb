module ZK
  # A Group is a basic membership primitive. You pick a name
  # for the group, and then join, leave, and receive updates when
  # group membership changes. You can also get a list of other members of the
  # group.
  #
  module Group
    # common znode data access
    module Common
      # the data my znode contains
      def data
        rval = nil
        synchronize { rval, self.last_stat = zk.get(path) }
        rval
      end

      # Set the data in my group znode (the data at {#path})
      # 
      # In the base implementation, no version is given, this will just
      # overwrite whatever is currently there.
      #
      # @param [String] val the data to set
      # @return [String] the data that was set
      def data=(val)
        synchronize { self.last_stat = zk.set(path, val) }
        val
      end
    end

    # A simple proxy for catching client errors and re-raising them as Group specific
    # errors (for clearer error reporting...we hope)
    #
    # @private
    class GroupExceptionTranslator
      def initialize(zk, group)
        @zk = zk
        @group = group
      end

      private
        def method_missing(m, *a, &b)
          super unless @zk.respond_to?(m)
          @zk.__send__(m, *a, &b)
        rescue Exceptions::NoNode
          raise Exceptions::GroupDoesNotExistError, "group at #{@group.path} has not been created yet", caller
        rescue Exceptions::NodeExists
          raise Exceptions::GroupAlreadyExistsError, "group at #{@group.path} already exists", caller
        end
    end
   
    # A simple proxy for catching client errors and re-raising them as Group specific
    # errors (for clearer error reporting...we hope)
    #
    # @private
    class MemberExceptionTranslator
      def initialize(zk)
        @zk = zk
      end

      private
        def method_missing(m, *a, &b)
          super unless @zk.respond_to?(m)
          @zk.__send__(m, *a, &b)
        rescue Exceptions::NoNode
          raise Exceptions::MemberDoesNotExistError, "group at #{path} has not been created yet", caller
        rescue Exceptions::NodeExists
          raise Exceptions::MemberAlreadyExistsError, "group at #{path} already exists", caller
        end
    end
  end
end

require 'zk/group/group_base'
require 'zk/group/member_base'

