require 'rubygems'

require 'zookeeper'

# XXX: after 1.0 we'll need this
# require 'zookeeper/compatibility'

require 'forwardable'
require 'thread'
require 'monitor'
require 'set'
require 'time'
require 'date'

module ZK
  # just like stdlib Monitor but provides the SAME API AS MUTEX, FFS!
  # @private
  class Monitor < Zookeeper::Monitor
  end
end

require 'zk/core_ext'
require 'zk/exceptions'
require 'zk/extensions'
require 'zk/logger'
require 'zk/event'
require 'zk/stat'
require 'zk/subscription'
require 'zk/fork_hook'
require 'zk/threadpool'
require 'zk/threaded_callback'
require 'zk/event_handler_subscription'
require 'zk/event_handler'
require 'zk/node_deletion_watcher'
require 'zk/message_queue'
require 'zk/locker'
require 'zk/election'
require 'zk/mongoid'
require 'zk/client'
require 'zk/pool'
require 'zk/find'

module ZK
  silence_warnings do
    # @private
    ZK_ROOT = File.expand_path('../..', __FILE__).freeze
  end

  unless defined?(KILL_TOKEN) 
    # @private
    KILL_TOKEN = Object.new 
  end

  @@logger = nil unless defined? @@logger
 
  @default_host   = 'localhost' unless @default_host
  @default_port   = 2181        unless @default_port
  @default_chroot = ''          unless @default_chroot

  class << self
    # what host should ZK.new connect to when given no options
    attr_accessor :default_host

    # what port should ZK.new connect to when given no options
    attr_accessor :default_port

    # what chroot path should ZK.new connect to when given no options
    attr_accessor :default_chroot
  end

  # The logger used by the ZK library. uses a Logger stderr with Logger::ERROR
  # level. The only thing that should ever be logged are exceptions that are
  # swallowed by background threads.
  #
  # You can change this logger by setting ZK#logger= to an object that
  # implements the stdllb Logger API.
  #
  def self.logger
    @@logger
  end

  # set the ZK logger instance
  def self.logger=(log)
    @@logger = log
  end

  # @private
  def self.default_connection_string
    "#{default_host}:#{default_port}".tap do |str|
      # XXX: this is seriously blech
      str.replace(File.join(str, default_chroot)) if default_chroot != ''
    end
  end

  # Create a new ZK::Client instance. If no arguments are given, the default
  # config of `localhost:2181` will be used. Otherwise all args will be passed
  # to ZK::Client#new
  #
  # if a block is given, it will be yielded the client *before* the connection
  # is established, this is useful for registering connected-state handlers.
  #
  # Since 1.0, if you pass a chrooted host string, i.e. `localhost:2181/foo/bar/baz` this
  # method will create two connections. The first will be short lived, and will create the 
  # chroot path, the second will be the chrooted one and returned to the user. This is
  # meant as a convenience to users who want to use chrooted connections.
  #
  # @note As it says in the ZooKeeper [documentation](http://zookeeper.apache.org/doc/r3.4.3/zookeeperProgrammers.html#ch_gotchas), 
  #   if you are running a cluster: "The list of ZooKeeper servers used by the
  #   client must match the list of ZooKeeper servers that each ZooKeeper
  #   server has. Things can work, although not optimally, if the client list
  #   is a subset of the real list of ZooKeeper servers, but not if the client
  #   lists ZooKeeper servers not in the ZooKeeper cluster."
  #
  # @example Connection using defaults
  #
  #   zk = ZK.new   # will connect to 'localhost:2181' 
  #
  # @example Connection to a single server
  #
  #   zk = ZK.new('localhost:2181')
  #
  # @example Connection to a single server with a chroot (automatically created)
  #
  #   zk = ZK.new('localhost:2181/look/around/you')
  #
  # @example Connection to multiple servers (a cluster)
  #   
  #   zk = ZK.new('server1:2181,server2:2181,server3:2181')
  #
  # @example Connection to multiple servers with a chroot (chroot will automatically be creatd)
  #
  #   zk = ZK.new('server1:2181,server2:2181,server3:2181/look/around/you')
  #
  # @example Connection to a single server, assert that chroot path exists, but do not create it
  #
  #   zk = ZK.new('localhost:2181/look/around/you', :chroot => :check)
  #
  # @example Connection to a single server, use a chrooted connection, do not check for validity, do not create
  # 
  #   zk = ZK.new('localhost:2181/look/around/you', :chroot => :do_nothing)
  #
  # @example Connection to a single server, chroot path specified as an option
  #
  #   zk = ZK.new('localhost:2181', :chroot => '/look/around/you')
  #
  # @overload new(connection_str, opts={}, &block)
  #   @param [String] connection_str A zookeeper host connection string, which
  #     is a comma-separated list of zookeeper servers and an optional chroot
  #     path.
  #
  #   @option opts [:create,:check,:do_nothing,String] :chroot (:create) if a chrooted
  #     `connection_str`, `:chroot` can have the following values:
  #
  #     * `:create` (the default), then we will use a secondary (short-lived)
  #     un-chrooted connection to ensure that the path exists before returning
  #     the chrooted connection. 
  #
  #     * `:check`, we will not attempt to create the connection, but rather
  #     will raise a {Exceptions::ChrootPathDoesNotExistError
  #     ChrootPathDoesNotExistError} if the path doesn't exist. 
  #
  #     * `:do_nothing`, we do not create the path and furthermore we do not
  #     perform the check (the `<= 0.9` behavior).
  #
  #     * if a `String` is given, it is used as the chroot path, and we will follow
  #     the same rules as if `:create` was given if `connection_str` also
  #     contains a chroot path, we raise an `ArgumentError`
  #
  #     * if you don't like this for some reason, you can always use
  #     {ZK::Client::Threaded#initialize Threaded.new} directly. You probably
  #     also hate happiness and laughter.
  #
  #   @option opts [:single,:per_callback] :thread (:single) see {ZK::Client::Threaded#initialize} 
  #     for a discussion of what these options mean
  #
  #   @raise [ChrootPathDoesNotExistError] if a chroot path is specified,
  #     `:chroot` is `:check`, and the path does not exist.
  #
  #   @raise [ArgumentError] if both a chrooted `connection_str` is given *and* a
  #     `String` value for the `:chroot` option is given
  #
  #
  def self.new(*args, &block)
    opts = args.extract_options!

    chroot_opt = opts.fetch(:chroot, :create)

    args = [default_connection_string]  if args.empty?     # the ZK.new() case

    if args.first.kind_of?(String)
      if new_cnx_str = do_chroot_setup(args.first, chroot_opt)
        args[0] = new_cnx_str
      end
    else
      raise ArgumentError, "cannot create a connection given args array: #{args}"
    end

    opts.delete(:chroot_opt)

    args << opts

    Client.new(*args, &block)
  end

  # Like new, yields a connection to the given block and closes it when the
  # block returns
  def self.open(*args)
    cnx = new(*args)
    yield cnx
  ensure
    if cnx
      cnx.close! 
      cnx.wait_until_closed(30) # XXX: hardcoded here, do not hang forever
    end
  end

  # creates a new ZK::Pool::Bounded with the default options.
  def self.new_pool(host, opts={})
    ZK::Pool::Bounded.new(host, opts)
  end

  # @private
  def self.join(*paths)
    File.join(*paths)
  end

  # @private
  def self.mri_19?
    ruby_19? and not jruby? or rubinius?
  end

  def self.mri_193?
    (RUBY_VERSION == '1.9.3') and not jruby? or rubinius?
  end

  def self.ruby_19?
    (RUBY_VERSION =~ /\A1\.9\.[2-9]\Z/)
  end

  def self.ruby_187?
    (RUBY_VERSION == '1.8.7')
  end

  # @private
  def self.mri_187?
    ruby_187? and not jruby? or rubinius?
  end

  # @private
  def self.jruby?
    defined?(::JRUBY_VERSION)
  end

  # @private
  def self.rubinius?
    defined?(::Rubinius)
  end

  private
    # @return [String] a possibly modified connection string (with chroot info
    #   added)
    #
    def self.do_chroot_setup(cnx_str, chroot_opt=:create)
      # "it should set up the chroot for us," they says. 
      # "it's confusing if it doesn't do that for us," they says.
      # sheesh, look at this...

      host, chroot_path = Client.split_chroot(cnx_str)

      case chroot_opt
      when :do_nothing
        return
      when String
        if chroot_path
          raise ArgumentError, "You cannot give a connection_str with a chroot path (#{cnx_str}) *and* specify a :chroot => #{chroot_opt} too!"
        else
          # ok, cnx_str didn't have a chroot path on it, but the user
          # specified :chroot => '/path'. we'll use that, then
          chroot_path = chroot_opt.dup
          chroot_opt  = :create

          # oh, and return the correct string later
          cnx_str = "#{host}#{chroot_path}"
        end
      when :create, :check
        # no-op, valid options for later
      else
        raise ArgumentError, ":chroot must be one of :create, :check, :do_nothing, or a String, not: #{chroot_opt.inspect}" 
      end

      return cnx_str unless chroot_path  # if by this point, we don't have a chroot_path, then there isn't one to be had

      # make sure the given path is kosher
      Client.assert_valid_chroot_str!(chroot_path)

      open(host) do |zk|                # do path stuff with the virgin connection
        unless zk.exists?(chroot_path)  # someting must be done
          if chroot_opt == :create      # here, let me...
            zk.mkdir_p(chroot_path)     # ...get that for you
          else                          # careful with that axe
            raise Exceptions::ChrootPathDoesNotExistError.new(host, chroot_path)  # ...eugene
          end                                                                               
        end
      end

      cnx_str   # the possibly-modified connection string (with chroot info)
    end
end
