# require 'rubygems'
# gem 'rdoc', '~> 2.5'
# require 'rdoc/task'

# RDoc::Task.new do |rd|
#   rd.title = 'ZK Documentation'
#   rd.rdoc_files.include("lib/**/*.rb")
# end

gemset_name = 'zk'

%w[1.8.7 1.9.2 1.9.3 jruby rbx].each do |ns_name|

  rvm_ruby = (ns_name == 'rbx') ? "rbx-2.0.testing" : ns_name

  ruby_with_gemset        = "#{rvm_ruby}@#{gemset_name}"
  create_gemset_task_name = "mb:#{ns_name}:create_gemset"
  bundle_task_name        = "mb:#{ns_name}:bundle_install"
  rspec_task_name         = "mb:#{ns_name}:run_rspec"

  task create_gemset_task_name do
    sh "rvm #{rvm_ruby} do rvm gemset create #{gemset_name}"
  end

  task bundle_task_name => create_gemset_task_name do
    rm_f 'Gemfile.lock'
    sh "rvm #{ruby_with_gemset} do bundle install"
  end

  task rspec_task_name => bundle_task_name do
    sh "rvm #{ruby_with_gemset} do bundle exec rspec spec --fail-fast"
  end

  task "mb:#{ns_name}" => rspec_task_name

  task "mb:test_all" => rspec_task_name
end

namespace :yard do
  task :clean do
    rm_rf '.yardoc'
  end

  task :server => :clean do
    sh "yard server --reload"
  end
end

namespace :spec do
  task :define do
    require 'rubygems'
    require 'bundler/setup'
    require 'rspec/core/rake_task'

    RSpec::Core::RakeTask.new('spec:runner')
  end

  task :run => :define do
    Rake::Task['spec:runner'].invoke
  end
end

task :default => 'spec:run'

