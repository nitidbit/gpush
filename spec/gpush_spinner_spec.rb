require "spec_helper"
require_relative "../src/ruby/gpush.rb"
require_relative "./mock_system.rb"

RSpec.describe "spinner option" do
  let(:mock_system) { MockSystem.new }
  # The spinner draws each command as "[<char>]<name>" on a single line
  let(:spinner_line) { /\[.\]parallel_run_1/ }
  let(:announcement) { /Running 2 commands: parallel_run_1, always skipped/ }

  before do
    Dir.chdir(__dir__)
    GitHelper.instance_variable_set(:@fetch_success, nil)
    allow(GitHelper).to receive(:head_sha).and_return("0123456")
    allow(Kernel).to receive(:system) do |*args|
      mock_system.mocked_system_call(
        args.reject { |a| a.is_a?(Hash) }.join(" "),
      )
    end
    allow(Kernel).to receive(:`).and_wrap_original do |_method, *args|
      mock_system.mocked_system_call(args.first)
    end
  end

  it "prints the spinner by default" do
    expect { GpushCli.run(%w[--dry-run]) }.to output(spinner_line).to_stdout
  end

  it "does not print the spinner with --no-spinner" do
    expect { GpushCli.run(%w[--dry-run --no-spinner]) }.not_to output(
      spinner_line,
    ).to_stdout
  end

  it "announces the commands instead of the spinner with --no-spinner" do
    expect { GpushCli.run(%w[--dry-run --no-spinner]) }.to output(
      announcement,
    ).to_stdout
  end

  it "still prints the summary with --no-spinner" do
    expect { GpushCli.run(%w[--dry-run --no-spinner]) }.to output(
      /Summary.*parallel_run_1: .*SUCCESS/m,
    ).to_stdout
  end

  context "with spinner: false in the config file" do
    before do
      expect(YAML).to receive(:load_file).exactly(:once).and_return(
        "spinner" => false,
        "parallel_run" => [
          { "name" => "parallel_run_1", "shell" => "echo hello" },
          {
            "name" => "always skipped",
            "shell" => "echo nope",
            "if" => "exit 1",
          },
        ],
      )
    end

    it "does not print the spinner" do
      expect { GpushCli.run(%w[--dry-run]) }.not_to output(
        spinner_line,
      ).to_stdout
    end

    it "is overridden by --spinner on the command line" do
      expect { GpushCli.run(%w[--dry-run --spinner]) }.to output(
        spinner_line,
      ).to_stdout
    end
  end

  context "reporting each command as it finishes" do
    before do
      expect(YAML).to receive(:load_file).exactly(:once).and_return(
        "parallel_run" => [
          { "name" => "slow", "shell" => "sleep 1" },
          { "name" => "fast", "shell" => "echo hello" },
          { "name" => "skipped one", "shell" => "echo nope", "if" => "exit 1" },
        ],
      )
    end

    def plain_output(args)
      original = $stdout
      $stdout = StringIO.new
      GpushCli.run(args)
      $stdout.string.gsub(/\e\[[\d;]*m/, "")
    ensure
      $stdout = original
    end

    it "prints each result with --no-spinner, before slower commands finish" do
      output = plain_output(%w[--dry-run --no-spinner])

      fast_done = output.index("fast: SUCCESS")
      expect(fast_done).to be < output.index("slow: SUCCESS")
      expect(output.index("skipped one: SKIPPED")).to be <
        output.index("Summary")
      expect(fast_done).to be < output.index("Summary")
    end

    it "leaves progress to the spinner when it is on" do
      output = plain_output(%w[--dry-run])

      expect(output.index("fast: SUCCESS")).to be > output.index("Summary")
    end
  end
end
