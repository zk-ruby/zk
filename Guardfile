# A sample Guardfile
# More info at https://github.com/guard/guard#readme

dot_rspec_path = File.expand_path('../.rspec', __FILE__)

rspec_options = File.open('.rspec', &:readlines).map(&:chomp).reject{|n| n =~ /\A(#|\Z)/}

guard 'bundler' do
  watch 'Gemfile'
  watch /\A.+\.gemspec\Z/
end

guard 'rspec', :version => 2 do
  watch(%r{^spec/.+_spec\.rb$})

  # run all specs when the support files change
  watch(%r{^spec/support/.+\.rb$}) { 'spec' }

  watch('spec/shared/client_examples.rb') { 'spec/zk/client_spec.rb' }

  watch(%r%^spec/support/client_forker.rb$%) { 'spec/zk/00_forked_client_integration_spec.rb' }

  watch(%r{^lib/(.+)\.rb$}) do |m| 
    case m[1]
    when 'zk/event_handler'
      "spec/zk/watch_spec.rb"

    when 'zk/client/threaded'
      ["spec/zk/client_spec.rb", "spec/zk/zookeeper_spec.rb"]

    when 'zk/locker'
      'spec/zk/locker_spec.rb'

    when %r{^(?:zk/locker/locker_base|spec/shared/locker)}
      Dir["spec/zk/locker/*_spec.rb"]

    when %r{^zk/client/(?:base|state_mixin|unixisms)}
      Dir['spec/zk/{client,client/*,zookeeper}_spec.rb']

    when 'zk' # .rb
      'spec'  # run all tests

    else
      generic = "spec/#{m[1]}_spec.rb"
      if test(?f, generic)
        generic
      else
        $stderr.puts "RUNNING ALL TESTS"
        'spec'
      end
    end
  end

  watch('spec/spec_helper.rb')  { "spec" }
end


