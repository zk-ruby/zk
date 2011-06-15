source "http://rubygems.org"
source "http://rubygems"
source "http://localhost:50000"

# Specify your gem's dependencies in zk.gemspec
gemspec

gem 'ruby-debug',   :platforms => [:mri_18, :jruby]
gem 'ruby-debug19', :platforms => :mri_19

git 'git://github.com/slyphon/zookeeper.git', :branch => 'dev/em' do
  gem 'slyphon-zookeeper', '~> 0.2.0'
end


# vim:ft=ruby
