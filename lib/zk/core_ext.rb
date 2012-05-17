# @private
class ::Exception
  unless method_defined?(:to_std_format)
    def to_std_format
      ary = ["#{self.class}: #{message}"]
      ary.concat(backtrace || [])
      ary.join("\n\t")
    end
  end
end

# @private
class ::Thread
  def zk_mongoid_lock_registry
    self[:_zk_mongoid_lock_registry]
  end

  def zk_mongoid_lock_registry=(obj)
    self[:_zk_mongoid_lock_registry] = obj
  end
end

# @private
class ::Hash
  # taken from ActiveSupport 3.0.12, but we don't replace it if it exists
  unless method_defined?(:extractable_options?)
    def extractable_options?
      instance_of?(Hash)
    end
  end
end

# @private
class ::Array
  unless method_defined?(:extract_options!)
    def extract_options!
      if last.is_a?(Hash) && last.extractable_options?
        pop
      else
        {}
      end
    end
  end

  # backport this from 1.9.x to 1.8.7
  #
  # this obviously cannot replicate the copy-on-write semantics of the 
  # 1.9.3 version, and only provides a naieve filtering functionality.
  #
  # also, does not handle the "returning an enumerator" case
  unless method_defined?(:select!)
    def select!(&b)
      replace(select(&b))
    end
  end
end

# @private
module ::Kernel
  unless method_defined?(:silence_warnings)
    def silence_warnings
      with_warnings(nil) { yield }
    end
  end

  unless method_defined?(:with_warnings)
    def with_warnings(flag)
      old_verbose, $VERBOSE = $VERBOSE, flag
      yield
    ensure
      $VERBOSE = old_verbose
    end
  end
end

# @private
class ::Module
  unless method_defined?(:alias_method_chain)
    def alias_method_chain(target, feature)
      # Strip out punctuation on predicates or bang methods since
      # e.g. target?_without_feature is not a valid method name.
      aliased_target, punctuation = target.to_s.sub(/([?!=])$/, ''), $1
      yield(aliased_target, punctuation) if block_given?

      with_method, without_method = "#{aliased_target}_with_#{feature}#{punctuation}", "#{aliased_target}_without_#{feature}#{punctuation}"

      alias_method without_method, target
      alias_method target, with_method

      case
        when public_method_defined?(without_method)
          public target
        when protected_method_defined?(without_method)
          protected target
        when private_method_defined?(without_method)
          private target
      end
    end
  end
end

require 'logger'

# lets you clone a a Logger instance but change properties, this is 
# used by the test suite to change the progname for different components
# @private
class ::Logger
  unless method_defined?(:clone_new_log)
    attr_writer :logdev

    def clone_new_log(opts={})
      self.class.new(nil).tap do |noo_log|
        noo_log.progname  = opts.fetch(:progname, self.progname)
        noo_log.formatter = opts.fetch(:formatter, self.formatter)
        noo_log.level     = opts.fetch(:level, self.level)
        noo_log.logdev    = @logdev
      end
    end
  end

  def debug_pp(title)
    debug do 
      str = "---< #{title} >---\n"
      require 'pp'
      str << PP.pp(yield, '') 
    end
  end
end


