RSpec::Matchers.define :exist do 
  match do |actual|
    actual.exists?
  end
end

