source :rubygems

# gem 'slyphon-zookeeper', :path => '~/zookeeper'
# gem 'zk-server', :path => '~/mbox/zk-server', :group => :test

gem 'rake', :group => [:development, :test]
gem 'pry',  :group => [:development]

group :docs do
  gem 'yard', '~> 0.7.5'

  platform :mri_19 do
    gem 'redcarpet'
  end
end

group :test do
  gem 'rspec', '~> 2.8.0'
  gem 'flexmock', '~> 0.8.10'
  gem 'zk-server', '~> 0.9.0'
end

# Specify your gem's dependencies in zk.gemspec
gemspec


# vim:ft=ruby
