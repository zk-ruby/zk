require 'spec_helper'

describe ZK::Client::Threaded do
  include_context 'threaded client connection'
  it_should_behave_like 'client'
end

