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

  watch(%r%^spec/support/client_forker.rb$%) { 'spec/zk/00_forked_client_integration_spec.rb' }

  watch(%r{^lib/(.+)\.rb$}) do |m| 
    case m[1]
    when %r{^zk/event_handler$}
      "spec/zk/watch_spec.rb"
    when %r{^zk/client/threaded.rb$}
      ["spec/zk/client_spec.rb", "spec/zk/zookeeper_spec.rb"]
    when %r{^zk/locker/}
      "spec/zk/locker_spec.rb"
    when %r{^zk\.rb$}
      'spec'  # run all tests
    else
      "spec/#{m[1]}_spec.rb"
    end
  end

  watch('spec/spec_helper.rb')  { "spec" }
end


