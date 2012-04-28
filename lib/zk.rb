require 'rubygems'

require 'logger'
require 'zookeeper'
require 'forwardable'
require 'thread'
require 'monitor'
require 'set'
require 'time'
require 'date'

require 'zk/logging'
require 'zk/exceptions'
require 'zk/extensions'
require 'zk/stat'
require 'zk/threadpool'
require 'zk/event_handler_subscription'
require 'zk/event_handler'
require 'zk/message_queue'
require 'zk/locker'
require 'zk/election'
require 'zk/mongoid'
require 'zk/client'
require 'zk/pool'
require 'zk/find'

module ZK
  ZK_ROOT = File.expand_path('../..', __FILE__) unless defined?(ZK_ROOT)

  KILL_TOKEN = Object.new unless defined?(KILL_TOKEN) 

  DEFAULT_SERVER = 'localhost:2181'.freeze unless defined?(DEFAULT_SERVER)

  unless @logger
    @logger = Logger.new($stderr).tap { |n| n.level = Logger::ERROR }
  end

  # The logger used by the ZK library. uses a Logger stderr with Logger::ERROR
  # level. The only thing that should ever be logged are exceptions that are
  # swallowed by background threads.
  #
  # You can change this logger by setting ZK#logger= to an object that
  # implements the stdllb Logger API.
  #
  def self.logger
    @logger
  end

  # Assign the Logger instance to be used by ZK
  def self.logger=(logger)
    @logger = logger
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
  # @example Connection to a single server with a chroot
  #
  #   zk = ZK.new('localhost:2181/you/are/over/here')
  #
  # @example Connection to multiple servers (a cluster)
  #   
  #   zk = ZK.new('server1:2181,server2:2181,server3:2181')
  #
  # @example Connection to multiple servers with a chroot
  #
  #   zk = ZK.new('server1:2181,server2:2181,server3:2181/you/are/over/here')
  #
  # @overload new(connection_str, opts={}, &block)
  #   @param [String] connection_str A zookeeper host connection string, which
  #     is a comma-separated list of zookeeper servers and an optional chroot
  #     path.
  #
  def self.new(*args, &block)
    opts = args.extract_options!

    create_chroot = opts.fetch(:create_chroot, true)

    if args.empty?
      args = [DEFAULT_SERVER] 
    elsif args.first.kind_of?(String)
      do_chroot_setup(args.first) if create_chroot
    else
      raise ArgumentError, "cannot create a connection given args array: #{args}"
    end

    opts.delete(:create_chroot)

    args << opts

    Client.new(*args, &block)
  end

  # Like new, yields a connection to the given block and closes it when the
  # block returns
  def self.open(*args)
    cnx = new(*args)
    yield cnx
  ensure
    cnx.close! if cnx
  end

  # creates a new ZK::Pool::Bounded with the default options.
  def self.new_pool(host, opts={})
    ZK::Pool::Bounded.new(host, opts)
  end

  # @private
  def self.join(*paths)
    File.join(*paths)
  end

  private
    def self.do_chroot_setup(host_str)
      host, chroot = Client.split_chroot(host_str)
      return unless chroot
      open(host) { |zk| zk.mkdir_p(chroot) }
    end
end

