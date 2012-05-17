module ZK
  # Provides common methods for pause and resume around a fork operation
  # assumes there is a @state that moves in the following ways
  #
  # * transition `:running -> :paused` when `pause_before_fork_in_parent` is called
  # * transition `:paused -> :running` when `resume_after_fork_in_parent` is called
  #
  # If either of those transitions is attempted without the correct starting state,
  # an InvalidStateError is assumed to be raised.
  #
  # None of these methods are synchronized, it is up to the including module to
  # handle that
  #
  module Suspendable

  protected
    def assert_pausable_state!
      raise InvalidStateError, "invalid state, expected to be :running, was #{@state.inspect}" if @state != :running
    end

    def assert_resumable_state!
      raise InvalidStateError, "expected :paused, was #{@state.inspect}" if @state != :paused
    end

    def transition_to_paused
      assert_pausable_state!
      return false if @state == :paused
      @state = :paused
    end

    def transition_to_running
    end
  end
end
