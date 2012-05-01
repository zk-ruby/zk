module Pendings
  def pending_192(msg)
    if RUBY_VERSION == '1.9.2' and not (jruby? or rubinius?)
      if block_given?
        pending(msg) { yield }
      else
        pending(msg)
      end
    else
      yield if block_given?
    end
  end

  def pending_187(msg)
    if RUBY_VERSION == '1.8.7' and not (jruby? or rubinius?)
      if block_given?
        pending(msg) { yield }
      else
        pending(msg)
      end
    else
      yield if block_given?
    end
  end

  def jruby?
    defined?(::JRUBY_VERSION)
  end

  def rubinius?
    defined?(::Rubinius)
  end
end

