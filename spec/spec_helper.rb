require "simplecov"
SimpleCov.start do
  add_filter "/spec/"
  add_filter "/vendor/"
  enable_coverage :branch
end

require "rspec"

RSpec.configure do |config|
  # Many specs chdir (in hooks or mid-example); restore the working directory
  # after each example so it can't leak into later specs.
  config.around do |example|
    original_dir = Dir.pwd
    example.run
  ensure
    Dir.chdir(original_dir)
  end

  config.before(:each) do
    # Otherwise a call to exit would quit the test suite
    allow(ExitHelper).to receive(:exit) do |code|
      raise "Exit called with code #{code}"
    end
  end
end
