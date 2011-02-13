
require 'zookeeper'
require 'forwardable'
require 'monitor'

require 'z_k/exceptions'
require 'z_k/event_handler_subscription'
require 'z_k/event_handler'
require 'z_k/message_queue'
require 'z_k/locker_base'
require 'z_k/locker'
require 'z_k/shared_locker'
require 'z_k/extensions'
require 'z_k/election'
require 'z_k/client'
require 'z_k/client_pool'

module ZK
  def self.new(*args)
    # XXX: might need to do some param parsing here
   
    opts = args.pop if args.last.kind_of?(Hash)
    args = %w[localhost:2181] if args.empty?

    # ignore opts for now
    Client.new(Zookeeper.new(*args))
  end

  def self.open(*args)
    cnx = new(*args)
    yield cnx
  ensure
    cnx.close! if cnx
  end
end

