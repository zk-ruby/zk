source "http://rubygems.org"
source "http://rubygems"
source "http://localhost:50000"

# Specify your gem's dependencies in zk.gemspec
gemspec

gem 'ruby-debug',   :platforms => [:mri_18, :jruby]

if RUBY_VERSION < '1.9.3'
  gem 'ruby-debug19', :platforms => :mri_19
end


# vim:ft=ruby
