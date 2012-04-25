# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "z_k/version"

Gem::Specification.new do |s|
  s.name        = "zk"
  s.version     = ZK::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Jonathan D. Simms", "Topper Bowers"]
  s.email       = ["simms@hp.com", "tobowers@hp.com"]
  s.homepage    = "https://github.com/slyphon/zk"
  s.summary     = %q{A high-level wrapper around the zookeeper driver}
  s.description = s.summary + "\n"

  s.add_runtime_dependency 'slyphon-zookeeper', '~> 0.9.0'

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
end
