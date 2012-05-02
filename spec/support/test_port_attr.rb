module ZK
  def self.spawn_zookeeper?
    !!ENV['SPAWN_ZOOKEEPER']
  end

  @test_port ||= spawn_zookeeper? ? 21811 : 2181

  class << self
    attr_accessor :test_port
  end
end

