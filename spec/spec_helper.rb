require "rspec"

RSpec.configure do |config|
  config.before(:each) do
    # Otherwise a call to exit would quit the test suite
    allow(ExitHelper).to receive(:exit) do |code|
      raise "Exit called with code #{code}"
    end
  end
end
