class EventCatcher
  extend Forwardable
  include ZK::Logger

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

  def add(*args)
    synchronize do
      case args.length
      when 2
        sym, obj = args
      when 1
        obj = args.first
        sym = obj.interest_key
      else
        raise ArgumentError, "Dunno how to handle args: #{args.inspect}" 
      end

      logger.debug { "adding #{sym.inspect} #{obj.inspect}" }
      events[sym] << obj
      cond(sym).broadcast

      events[:all] << obj
      cond(:all).broadcast
    end
  end
  alias << add

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
        wait_for(:#{name}, timeout)
      end

      def wait_while_#{name}(&blk)
        wait_while(:#{name}, &blk)
      end

      def wait_until_#{name}(&blk)
        wait_until(:#{name}, &blk)
      end
    EOS
  end
end 
