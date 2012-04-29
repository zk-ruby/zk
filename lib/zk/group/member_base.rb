module ZK
  module Group
    class MemberBase
      include Common

      attr_reader :zk 

      # @return [Group] the group instance this member belongs to
      attr_reader :group

      # @return [String] the relative path of this member under `group.path`
      attr_reader :name

      # @return [String] the absolute path of this member
      attr_reader :path

      def initialize(zk, group, path)
        @zk = zk
        @group = group
        @path = path
        @name = File.basename(@path)
      end

      # probably poor choice of name, but does this member still an active membership
      # to its group (i.e. is its path still good). 
      #
      # This will return false after leave is called.
      def active?
        zk.exists?(path)
      end

      # Leave the group this membership is associated with.
      # In the basic implementation, this is not meant to kick another member
      # out of the group.
      #
      # @abstract Implement 'leaving' behavior in subclasses
      def leave
        zk.delete(path)
      end
    end # MemberBase
  end # Group
end # ZK


