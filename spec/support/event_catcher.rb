class EventCatcher
  extend Forwardable
  include ZK::Logging

  def_delegators :@mutex, :synchronize

  MEMBERS = [:created, :changed, :deleted, :child, :all]

  attr_reader :events, :mutex
    
  def initialize(*args)
    @mutex = Monitor.new
    @conds = {}
    @events = {}

    MEMBERS.each do |k|
      @conds[k] = @mutex.new_cond
      @events[k] = []
    end
  end

  def cond(name)
    @conds.fetch(name)
  end

  def clear_all
    synchronize do
      @events.values.each(&:clear)
    end
  end

  def add(sym,obj)
    synchronize do
      logger.debug { "adding #{sym.inspect} #{obj.inspect}" }
      events[sym] << obj
      cond(sym).broadcast

      events[:all] << obj
      cond(:all).broadcast
    end
  end

  def wait_for(ev_name, timeout=5)
    cond(ev_name).wait(timeout)
  end

  def wait_while(ev_name)
    cond(ev_name).wait_while { yield @events.fetch(ev_name) }
  end

  def wait_until(ev_name)
    cond(ev_name).wait_until { yield @events.fetch(ev_name) }
  end

  MEMBERS.each do |name|
    class_eval <<-EOS, __FILE__, __LINE__+1
      def #{name}
        events[:#{name}]
      end

      def cond_#{name}
        cond(:#{name})
      end

      # waits for an event group to not be empty (up to timeout sec)
      def wait_for_#{name}(timeout=5)
        cond(:#{name}).wait(timeout)
      end

      def wait_while_#{name}
        cond(:#{name}).wait_while { yield __send__(:#{name}) }
      end

      def wait_until_#{name}
        cond(:#{name}).wait_until { yield __send__(:#{name}) }
      end
    EOS
  end
end 
