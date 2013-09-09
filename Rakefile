release_ops_path = File.expand_path('../releaseops/lib', __FILE__)

# if the special submodule is availabe, use it
# we use a submodule because it doesn't depend on anything else (*cough* bundler)
# and can be shared across projects
#
if File.exists?(release_ops_path)
  require File.join(release_ops_path, 'releaseops')

  # sets up the multi-ruby zk:test_all rake tasks
  ReleaseOps::TestTasks.define_for(*%w[1.8.7 1.9.2 jruby-1.6.8 ree 1.9.3])

  # sets up the task :default => 'spec:run' and defines a simple
  # "run the specs with the current rvm profile" task
  ReleaseOps::TestTasks.define_simple_default_for_travis

  # Define a task to run code coverage tests
  ReleaseOps::TestTasks.define_simplecov_tasks

  # set up yard:server, yard:gems, and yard:clean tasks 
  # for doing documentation stuff
  ReleaseOps::YardTasks.define

  namespace :zk do
    namespace :gems do
      task :build do
        require 'tmpdir'

        raise "You must specify a TAG" unless ENV['TAG']

        ReleaseOps.with_tmpdir(:prefix => 'zk') do |tmpdir|
          tag = ENV['TAG']

          sh "git clone . #{tmpdir}"

          orig_dir = Dir.getwd

          cd tmpdir do
            sh "git co #{tag} && git reset --hard && git clean -fdx"

            sh "gem build zk.gemspec"

            mv FileList['*.gem'], orig_dir
          end
        end
      end

      task :push do
        gems = FileList['*.gem']
        raise "No gemfiles to push!" if gems.empty?

        gems.each do |gem|
          sh "gem push #{gem}"
        end
      end

      task :clean do
        rm_rf FileList['*.gem']
      end

      task :all => [:build, :push, :clean]
    end
  end


  task :clean => 'yard:clean'
end

