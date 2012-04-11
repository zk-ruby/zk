# require 'rubygems'
# gem 'rdoc', '~> 2.5'
# require 'rdoc/task'

# RDoc::Task.new do |rd|
#   rd.title = 'ZK Documentation'
#   rd.rdoc_files.include("lib/**/*.rb")
# end

gemset_name = 'zk'

%w[1.9.3 jruby].each do |rvm_ruby|
  ruby_with_gemset = "#{rvm_ruby}@#{gemset_name}"
  bundle_task_name  = "mb:#{rvm_ruby}:bundle_install"
  rspec_task_name   = "mb:#{rvm_ruby}:run_rspec"

  task bundle_task_name do
    rm_f 'Gemfile.lock'
    sh "rvm #{ruby_with_gemset} do bundle install"
  end

  task rspec_task_name => bundle_task_name do
    sh "rvm #{ruby_with_gemset} do bundle exec rspec spec --fail-fast"
  end

  task "mb:test_all_rubies" => rspec_task_name
end

