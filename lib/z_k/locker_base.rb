module ZK
  class LockerBase
    # @private
    attr_accessor :zk

    # our absolute lock node path
    #
    # ex. '/_zklocking/foobar/__blah/lock000000007'
    attr_reader :lock_path #;nodoc:

    def self.digit_from_lock_path(path) #:nodoc:
      path[/0*(\d+)$/, 1].to_i
    end

    def initialize(zookeeper_client, name, root_lock_node = "/_zklocking") 
      @zk = zookeeper_client
      @root_lock_node = root_lock_node
      @path = name
      @locked = false
    end

    # the basename of our lock path
    #
    # for the lock_path '/_zklocking/foobar/__blah/lock000000007'
    # lock_basename is 'lock000000007'
    #
    # returns nil if lock_path is not set
    def lock_basename
      lock_path and File.basename(lock_path)
    end

    def root_lock_path #:nodoc:
      @root_lock_path ||= "#{@root_lock_node}/#{@path.gsub("/", "__")}"
    end

    def locked?
      false|@locked
    end
    
    def unlock!
      if @locked
        cleanup_lock_path!
        @locked = false
        true
      end
    end

    protected 
      def digit_from(path)
        self.class.digit_from_lock_path(path)
      end

      def lock_children(watch=false)
        @zk.children(root_lock_path, :watch => watch)
      end

      def ordered_lock_children(watch=false)
        lock_children(watch).tap do |ary|
          ary.sort! { |a,b| digit_from(a) <=> digit_from(b) }
        end
      end

      def create_root_path!
        @zk.mkdir_p(root_lock_path)
      end

      # prefix is the string that will appear in front of the sequence num,
      # defaults to 'lock'
      def create_lock_path!(prefix='lock')
        create_root_path!
        @lock_path = @zk.create("#{root_lock_path}/#{prefix}", "", :mode => :ephemeral_sequential)
      rescue Exceptions::NoNode
        retry
      end

      def cleanup_lock_path!
        @zk.delete(@lock_path)
        @zk.delete(root_lock_path) rescue Exceptions::NotEmpty
      end
  end
end

