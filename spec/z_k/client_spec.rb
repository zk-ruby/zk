require 'spec_helper'
require 'shared/client_examples'

describe ZK::Client::Threaded do
  include_context 'threaded client connection'
  it_should_behave_like 'client'
end

