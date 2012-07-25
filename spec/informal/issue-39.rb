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

  PATH = '/issue-39'

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

  def handle_event(event)
    zk.stat(PATH, :watch => true)
    logger.info { "got event #{event.class.inspect}" } 
  end

  def iterate
    sigcont_zookeeper

    zk.rm_rf(PATH)
    zk.mkdir_p(PATH)

    zk.on_connected(&method(:handle_event))
    zk.register(PATH, &method(:handle_event))

    p zk.stat(PATH, :watch => true)

    sigstop_zookeeper

    threads = []

    20.times do 
      threads << Thread.new do 
        sleep rand
        zk.get(PATH, :watch => true)
      end
    end  

    threads.each do |th| 
      logger.debug { "joining thread: #{th}" }
      begin
        th.join
      rescue Zookeeper::Exceptions::NotConnected => e
        logger.error { "boring! #{e.class}" }
      rescue Exception => e
        @mutex.synchronize do
          logger.error(e)
        end
      end
    end
  ensure
    sigcont_zookeeper
  end

  def main
    10.times { iterate }
  end
end

Issue39.new.main if __FILE__ == $0

