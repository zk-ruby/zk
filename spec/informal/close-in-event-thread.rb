#!/usr/bin/env ruby

require 'zk'

LOG = Logger.new($stderr).tap { |n| n.level = Logger::DEBUG }

ZK.logger = LOG
Zookeeper.logger = LOG

class CloseInEventThread
  include Zookeeper::Constants

  def initialize
    @zk = ZK.new
    @q = Queue.new
  end

  def run
    @zk.on_connecting do |event|
      if @ok_do_it
        logger.debug { "ok, calling close, in event thread? #{@zk.event_dispatch_thread?}" }
        @zk.close! 
        logger.debug { "close! returned, continuing" }
        @q.push(:OK)
      else
        logger.debug { "on_connecting, got event #{event}" }
      end
    end

    @ok_do_it = true
    logger.debug { "push bogus ZOO_CONNECTING_STATE event into queue" }
    @zk.__send__(:cnx).event_queue.push(:req_id => -1, :type => -1, :state => ZOO_CONNECTING_STATE, :path => '')

    rval = @q.pop

    logger.debug { "got #{rval.inspect}" }

    @zk.close!
  end

  def logger
    LOG
  end
end

CloseInEventThread.new.run

