#!/usr/bin/env ruby

require 'zk'

class WhatTheFork

  def initialize
    @zk = ZK.new
    @base_path = '/what-the-fork'
    @path_to_delete = "#{@base_path}/delete_me"
  end

  def run
    @zk.mkdir_p(@path_to_delete)

    @zk.on_connected do |event|
      $stderr.puts  "on_connected: #{event.inspect}"
    end

    @zk.on_connecting do |event|
      $stderr.puts "on_connecting: #{event.inspect}"
    end

    @zk.on_expired_session do |event|
      $stderr.puts "on_expired_session: #{event.inspect}"
    end

    fork_it!
  end

  def fork_it!
    pid = fork do
      $stderr.puts "closing zk"
      @zk.close!
      $stderr.puts "closed zk"
      @zk = ZK.new
      $stderr.puts "created new zk"

      @zk.delete(@path_to_delete)

      $stderr.puts "deleted path #{@path_to_delete}, closing new zk instance"

      @zk.close!

      $stderr.puts  "EXITING!!"
      exit 0
    end

    _, stat = Process.waitpid2(pid)
    $stderr.puts "child exited, stat: #{stat.inspect}"
  ensure
    if pid
      $stderr.puts "ensuring #{pid} is really dead"
      Process.kill(9, pid) rescue Errno::ESRCH
    end
  end

  def logger
    @logger
  end
end

WhatTheFork.new.run if __FILE__ == $0

