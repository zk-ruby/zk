class BogusMongoid
  include ZK::Mongoid::Locking
  include ZK::Logging

  attr_reader :id

  def initialize(opts={})
    @id = opts[:id] || 42
  end
end

