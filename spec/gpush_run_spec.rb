require "rspec"
require_relative "../src/ruby/gpush_run.rb"

RSpec.describe "gpush run" do
  before do
    Dir.chdir(__dir__) # Change to the directory of the current spec file

    allow(ExitHelper).to receive(:exit) do |code|
      raise "Exit called with code #{code}"
    end
  end

  it "should run the specified command from parallel_run section" do
    expect { GpushRun.go(args: ["parallel_run_1"], options: {}) }.to output(
      %r{Parallel run 1 in spec/gpushrc\.yml},
    ).to_stdout.and raise_error("Exit called with code 0")
  end

  it "should be a little fuzzy with spaces in the command name" do
    expect { GpushRun.go(args: ["parallel run 1"], options: {}) }.to output(
      %r{Parallel run 1 in spec/gpushrc\.yml},
    ).to_stdout.and raise_error("Exit called with code 0")
  end

  it "should exit with error when command not found in parallel_run" do
    expect {
      GpushRun.go(args: ["nonexistent_command"], options: {})
    }.to output(
      /Command not found: nonexistent_command/,
    ).to_stdout.and raise_error("Exit called with code 1")
  end
end
