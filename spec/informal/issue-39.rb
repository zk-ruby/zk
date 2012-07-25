#!/usr/bin/env ruby

ENV['ZK_DEBUG'] = ENV['ZOOKEEPER_DEBUG'] = '1'

require 'rubygems'
require 'bundler/setup'

require 'zk'
require 'pp'


# load File.expand_path('../../support/logging.rb', __FILE__)

Kernel.srand(1)

class Issue39
  attr_reader :logger, :zk

  def initialize
    @mutex = Monitor.new
    @logger = Logging::Logger.root
    @logger.level = :debug
    @logger.add_appenders(Logging.appenders.stderr)

    Logging.logger['Zookeeper'].level = :debug
    @zk = ZK.new('localhost:2181')
  end

  def zookeeper_pid
    line = `ps auwwx`.split("\n").grep(/org\.apache\.zookeeper\.server\.quorum\.QuorumPeerMain/).first
    raise "Could not find zookeeper process in ps output" unless line

    line.split(/\s+/).at(1).to_i
  end

  def sigstop_zookeeper
    logger.warn { "Sending STOP to zookeeper pid: #{zookeeper_pid}" }
    Process.kill('STOP', zookeeper_pid)
  end

  def sigcont_zookeeper
    logger.warn { "Sending CONT to zookeeper pid: #{zookeeper_pid}" }
    Process.kill('CONT', zookeeper_pid)
  end

  def main
    sigcont_zookeeper

    p zk.stat('/')

    sigstop_zookeeper

    threads = []

    20.times do 
      threads << Thread.new do 
        sleep rand
        zk.get('/', :watch => true)
      end
    end  

    threads.each do |th| 
      logger.debug { "joining thread: #{th}" }
      begin
        th.join
      rescue Exception => e
        @mutex.synchronize do
          logger.error(e)
        end
      end
    end
  ensure
    sigcont_zookeeper
  end
end

Issue39.new.main if __FILE__ == $0

