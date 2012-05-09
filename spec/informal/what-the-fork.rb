#!/usr/bin/env ruby

require 'zk'

def new_stderr_logger
  Logger.new($stderr).tap { |l| l.level = Logger::DEBUG }
end

ZK.logger = new_stderr_logger

class WhatTheFork
  attr_reader :logger

  def initialize
    @zk = ZK.new
    @base_path = '/what-the-fork'
    @path_to_delete = "#{@base_path}/delete_me"
  end

  def setup_logs!
    Zookeeper.logger = ZK.logger = @logger = new_stderr_logger
  end

  def run
    setup_logs!

    @zk.mkdir_p(@path_to_delete)

    @zk.on_connected do |event|
      _debug  "on_connected: #{event.inspect}"
    end

    @zk.on_connecting do |event|
      _debug "on_connecting: #{event.inspect}"
    end

    @zk.on_expired_session do |event|
      _debug "on_expired_session: #{event.inspect}"
    end

    fork_it!

    @zk.block_until_node_deleted(@path_to_delete)
    _debug "exiting main process!"
  end

  def fork_it!
    pid = fork do
      setup_logs!

      _debug "closing zk"
      @zk.close!
      _debug "closed zk"
      @zk = ZK.new
      _debug "created new zk"

      @zk.delete(@path_to_delete)

      _debug "deleted path #{@path_to_delete}, closing new zk instance"

      @zk.close!

      _debug  "EXITING!!"
      exit 0
    end

    _, stat = Process.waitpid2(pid)
    _debug "child exited, stat: #{stat.inspect}"
  ensure
    if pid
      _debug "ensuring #{pid} is really dead"
      begin
        Process.kill(9, pid) 
      rescue Errno::ESRCH
      end
    end
  end

  def _debug(str)
    logger.debug { str }
  end
end

WhatTheFork.new.run if __FILE__ == $0

