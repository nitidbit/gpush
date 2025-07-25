require "rspec"
require_relative "../src/ruby/gpush.rb"

RSpec.describe "gpush run" do
  before do
    Dir.chdir(__dir__) # Change to the directory of the current spec file
  end

  it "should run the specified command from parallel_run section" do
    expect { Gpush.cl(%w[run parallel_run_1]) }.to output(
      %r{Parallel run 1 in spec/gpushrc\.yml},
    ).to_stdout.and raise_error("Exit called with code 0")
  end

  it "should be a little fuzzy with spaces in the command name" do
    expect { Gpush.cl(%w[run parallel_run_1]) }.to output(
      %r{Parallel run 1 in spec/gpushrc\.yml},
    ).to_stdout.and raise_error("Exit called with code 0")
  end

  it "should exit with error when command not found in parallel_run" do
    expect { Gpush.cl(%w[run nonexistent_command]) }.to output(
      /Command not found: nonexistent_command/,
    ).to_stdout.and raise_error("Exit called with code 1")
  end

  it "skips commands that fail the 'if' condition" do
    expect { Gpush.cl(%w[run always_skipped]) }.to output(
      /always skipped skipped because 'if' condition failed(?!.*should never run)/m,
    ).to_stdout.and raise_error("Exit called with code 1")
  end
end
