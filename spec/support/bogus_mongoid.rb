class BogusMongoid
  include ZK::Mongoid::Locking

  attr_reader :id

  def initialize(opts={})
    @id = opts[:id] || 42
  end
end

