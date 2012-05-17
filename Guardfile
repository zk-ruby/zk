# A sample Guardfile
# More info at https://github.com/guard/guard#readme

dot_rspec_path = File.expand_path('../.rspec', __FILE__)

rspec_options = File.open('.rspec', &:readlines).map(&:chomp).reject{|n| n =~ /\A(#|\Z)/}

guard 'rspec', :version => 2 do
  watch(%r{^spec/.+_spec\.rb$})

  watch(%r{^lib/(.+)\.rb$}) do |m| 
    case m[1]
    when %r%\Azk/event_handler%
      "spec/zk/watch_spec.rb"
    else
      "spec/#{m[1]}_spec.rb"
    end
  end

  watch('spec/spec_helper.rb')  { "spec" }
end

