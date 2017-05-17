source "https://rubygems.org"

# gem 'slyphon-zookeeper', :path => '~/zookeeper'

# gem 'zookeeper', :path => "~/zookeeper"

# this is the last known commit that we tested against and is passing.
# keep closer track of this stuff to make bisecting easier and travis more
# accurate

# git 'git://github.com/slyphon/zookeeper.git', :tag => 'dev/zk/00013' do
#   gem 'zookeeper', '~> 1.3.0'
# end

group :development, :test do
  if RUBY_VERSION >= '1.9.3'
    gem 'rake'
  else
    gem 'rake', '~> 10.5'
  end
end

group :docs do
  gem 'yard', '~> 0.8.0'

  platform :mri_19 do
    gem 'redcarpet'
  end
end

# platform :mri_19 do
#   gem 'simplecov', :group => :coverage, :require => false
# end

group :development do
  gem 'guard',          :require => false
  gem 'guard-rspec',    :require => false
  gem 'guard-shell',    :require => false
  gem 'guard-bundler',  :require => false

  if RUBY_PLATFORM =~ /darwin/i
    gem 'growl',       :require => false
    gem 'rb-readline', :platform => :ruby
  end

  gem 'pry'

  platform :mri do
    gem 'pry-byebug'
  end
end

group :test do
  gem 'rspec', '~> 3.6.0'
  gem 'zk-server', '~> 1.1.4'
  gem 'test-unit', :platforms => [:ruby_22, :ruby_23, :ruby_24]
end

# Specify your gem's dependencies in zk.gemspec
gemspec


# vim:ft=ruby
