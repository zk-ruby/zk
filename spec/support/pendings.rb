module Pendings
  def pending_192(msg)
    if ZK.mri_19x?
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
    if ZK.mri_187?
      if block_given?
        pending(msg) { yield }
      else
        pending(msg)
      end
    else
      yield if block_given?
    end
  end

  def pending_jruby19(msg)
    if ZK.ruby_19? and ZK.jruby?
      if block_given?
        pending(msg) { yield }
      else
        pending(msg)
      end
    else
      yield if block_given?
    end
  end

  def pending_rbx(msg)
    if ZK.rubinius?
      if block_given?
        pending(msg) { yield }
      else
        pending(msg)
      end
    else
      yield if block_given?
    end
  end
  alias pending_rubinius pending_rbx

  def pending_in_travis(msg)
    # defined in the somewhat ill-named 00_test_port_attr.rb
    if ZK.travis?
      if block_given?
        pending("TRAVIS: #{msg}") { yield }
      else
        pending("TRAVIS: #{msg}")
      end
    else
      yield if block_given?
    end
  end
end

