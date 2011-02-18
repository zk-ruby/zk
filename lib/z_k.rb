require 'rubygems'
require 'bundler/setup'

require 'logger'
require 'zookeeper'
require 'forwardable'
require 'thread'
require 'monitor'

require 'z_k/logging'
require 'z_k/exceptions'
require 'z_k/threadpool'
require 'z_k/event_handler_subscription'
require 'z_k/event_handler'
require 'z_k/message_queue'
require 'z_k/locker_base'
require 'z_k/locker'
require 'z_k/shared_locker'
require 'z_k/extensions'
require 'z_k/election'
require 'z_k/mongoid'
require 'z_k/client'
require 'z_k/pool'

module ZK
  ZK_ROOT = File.expand_path('../..', __FILE__)

  KILL_TOKEN = :__kill_token__ #:nodoc:


  # The logger used by the ZK library. uses a Logger to +/dev/null+ by default
  #
  def self.logger
    @logger ||= Logger.new('/dev/null')
  end

  # Assign the Logger instance to be used by ZK
  def self.logger=(logger)
    @logger = logger
  end

  # Create a new ZK::Client instance. If no arguments are given, the default
  # config of 'localhost:2181' will be used. Otherwise all args will be passed
  # to ZK::Client#new
  #
  def self.new(*args)
    # XXX: might need to do some param parsing here
   
    opts = args.pop if args.last.kind_of?(Hash)
    args = %w[localhost:2181] if args.empty?

    # ignore opts for now
    Client.new(*args)
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
end

