#!/usr/bin/env ruby

require 'rubygems'
require 'zk'

class ::Exception
  def to_std_format
    "#{self.class}: #{message}\n" + backtrace {|n| "\t#{n}"}.join("\n")
  end
end

def safe_join(th, timeout=nil)
  begin
    th.join(timeout)
  rescue Exception => e
    $stderr.puts "#{th[:name]} raised #{e.to_std_format}"
  end
end

def print_error
  yield
rescue Exception => e
  $stderr.puts "caught exception in #{Thread.current[:name]}: #{e.to_std_format}"
end

lock_name = 'the_big_sleep'

q = Queue.new

th1 = Thread.new do
  ZK.open do |zk|
    $stderr.puts "first connection session_id: 0x%x" % zk.session_id

    zk.with_lock(lock_name) do
      q.push(:ok_sleeping)
      sleep # we now sleep with the fishes
    end
  end
end

th1[:name] = 'thread 1'

q.pop

Thread.pass until th1.status == 'sleep'

$stderr.puts "ok, now try to acquire lock"

th2 = Thread.new do
  ZK.open do |zk|
    $stderr.puts "second connection session_id: 0x%x" % zk.session_id

    zk.with_lock(lock_name) do
      $stderr.puts "acquired the lock in second thread"
    end
  end
end

th2[:name] = 'thread 2'

[th1, th2].each(&method(:safe_join))

