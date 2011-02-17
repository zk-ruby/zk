require 'bundler'
Bundler::GemHelper.install_tasks

require 'rubygems'
gem 'rdoc', '~> 2.5'
require 'rdoc/task'

RDoc::Task.new do |rd|
  rd.title = 'ZK Documentation'
  rd.rdoc_files.include("lib/**/*.rb")
end


