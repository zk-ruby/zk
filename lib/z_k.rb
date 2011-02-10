require 'zookeeper'

require 'z_k/exceptions'
require 'z_k/callbacks'
require 'z_k/event_handler'
require 'z_k/client'

module ZK
  def self.new(*args)
    # XXX: might need to do some param parsing here
    Client.new(Zookeeper.new(*args))
  end
end

