module ZK
  # Included in Zookeeper::Stat, extends it with some conveniences for 
  # dealing with Stat objects. Also provides docuemntation here for the meaning
  # of these values.
  #
  # Some of the methods added are to match the names in [the documentation][]
  #
  # Some of this may eventually be pushed down to slyphon-zookeeper
  #
  # [the documentation]: http://zookeeper.apache.org/doc/r3.3.5/zookeeperProgrammers.html#sc_zkStatStructure
  module Stat
    MEMBERS = [:version, :exists, :czxid, :mzxid, :ctime, :mtime, :cversion, :aversion, :ephemeralOwner, :dataLength, :numChildren, :pzxid].freeze

    def ==(other)
      MEMBERS.all? { |m| self.__send__(m) == other.__send__(m) }
    end

    # returns true if the node is ephemeral (will be cleaned up when the
    # current session expires)
    def ephemeral?
      ephemeral_owner && (ephemeral_owner != 0)
    end

    # The zxid of the change that caused this znode to be created.
    #
    # (also: czxid)
    def created_zxid
      # @!parse alias czxid created_zxid
      czxid
    end

    # The zxid of the change that last modified this znode.
    #
    # (also: mzxid)
    def last_modified_zxid
      mzxid
    end

    # The time in milliseconds from epoch when this znode was created
    # 
    # (also: created\_time)
    #
    # @return [Fixnum] 
    # @see #ctime_t 
    def created_time
      ctime
    end

    # The time when this znode was created
    #
    # @return [Time] creation time of this znode
    def ctime_t
      Time.at(ctime * 0.001)
    end

    # The time in milliseconds from epoch when this znode was last modified.
    #
    # (also: mtime)
    # @return [Fixnum]
    # @see #mtime_t
    def last_modified_time
      mtime
    end

    # The time when this znode was last modified
    #
    # @return [Time] last modification time of this znode
    # @see #last_modified_time
    def mtime_t
      Time.at(mtime * 0.001)
    end

    # The number of changes to the children of this znode
    #
    # (also: #cversion)
    # @return [Fixnum]
    def child_list_version
      cversion
    end

    # The number of changes to the ACL of this znode.
    #
    # (also: #aversion)
    # @return [Fixnum]
    def acl_list_version
      aversion
    end

    # The number of changes to the data of this znode.
    #
    # @return [Fixnum]
    def version
      super
    end

    # The length of the data field of this znode.
    #
    # @return [Fixnum]
    def data_length
      super
    end

    # The number of children of this znode.
    #
    # @return [Fixnum]
    def num_children
      super
    end
  end # Stat
end # ZK

class Zookeeper::Stat
  include ZK::Stat
end

