module ZK
  def self.spawn_zookeeper?
    !!ENV['SPAWN_ZOOKEEPER']
  end

  def self.travis?
    !!ENV['TRAVIS']
  end

  @test_port ||= spawn_zookeeper? ? 21811 : 2181

  class << self
    attr_accessor :test_port
  end

  # argh, blah, this affects ZK.new everywhere (which is kind of the point, but
  # still gross)
  self.default_port = self.test_port

  # only for testing is this done
  if host = ENV['ZK_DEFAULT_HOST']
    self.default_host = host
  end
end

