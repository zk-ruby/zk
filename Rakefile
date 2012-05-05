RELEASE_OPS_PATH = File.expand_path('../releaseops/lib', __FILE__)

# if the special submodule is availabe, use it
if File.exists?(RELEASE_OPS_PATH)
  $stderr.puts "RELEASE_OPS_PATH: #{RELEASE_OPS_PATH}"
  $LOAD_PATH.unshift(RELEASE_OPS_PATH).uniq!
  require 'releaseops'

  ReleaseOps::TestTasks.define_for(*%w[1.8.7 1.9.2 jruby rbx ree 1.9.3])
  ReleaseOps::YardTasks.define

  task :clean => 'yard:clean'
end

namespace :spec do
  task :define do
    require 'rubygems'
    require 'bundler/setup'
    require 'rspec/core/rake_task'

    RSpec::Core::RakeTask.new('spec:runner') do |t|
      t.rspec_opts = '-f d' if ENV['TRAVIS']
    end
  end

  task :run => :define do
    Rake::Task['spec:runner'].invoke
  end
end

task :default => 'spec:run'

