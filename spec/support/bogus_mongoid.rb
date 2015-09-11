class BogusMongoid
  include ZK::Mongoid::Locking
  include ZK::Logger

  attr_reader :id

  def initialize(opts={})
    @id = opts[:id] || 42
  end
end

