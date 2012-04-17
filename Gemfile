# this is here for doing internal builds in our environment
source ENV['MBOX_BUNDLER_SOURCE'] if ENV['MBOX_BUNDLER_SOURCE']
source "http://rubygems.org"

group :development do
  gem 'pry'
end

group :test do
  gem 'ZenTest', '~> 4.5.0'
end

# Specify your gem's dependencies in zk.gemspec
gemspec


# vim:ft=ruby
