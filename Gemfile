source :rubygems

# gem 'slyphon-zookeeper', :path => '~/zookeeper'

#gem 'zookeeper', :path => "~/zookeeper"

git 'git://github.com/slyphon/zookeeper.git', :branch => 'master' do
  gem 'zookeeper', '>= 1.0.0.beta.1'
end


gem 'rake', :group => [:development, :test]
gem 'pry',  :group => [:development]

group :docs do
  gem 'yard', '~> 0.8.0'

  platform :mri_19 do
    gem 'redcarpet'
  end
end

group :test do
  gem 'rspec', '~> 2.8.0'
  gem 'flexmock', '~> 0.8.10'
  gem 'zk-server', '~> 1.0.1'
end

# Specify your gem's dependencies in zk.gemspec
gemspec


# vim:ft=ruby
