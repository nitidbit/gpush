require "spec_helper"
require_relative "../src/ruby/gpush.rb"
require_relative "./mock_system.rb"

RSpec.describe "--skip" do
  let(:mock_system) { MockSystem.new }
  let(:config) do
    {
      "pre_run" => [{ "name" => "setup", "shell" => "echo SETUP-RAN" }],
      "parallel_run" => [
        { "name" => "rspec", "shell" => "echo RSPEC-RAN" },
        { "name" => "Brakeman", "shell" => "echo BRAKEMAN-RAN" },
        { "shell" => "echo UNNAMED-RAN" },
      ],
      "post_run" => [{ "name" => "report", "shell" => "echo REPORT-RAN" }],
    }
  end

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
    allow(YAML).to receive(:load_file).and_return(config)
  end

  def run_gpush(*args)
    output = StringIO.new
    original_stdout = $stdout
    $stdout = output
    error = nil
    begin
      GpushCli.run(["--dry-run", "-v", *args])
    rescue RuntimeError => e
      error = e
    ensure
      $stdout = original_stdout
    end
    [output.string, error]
  end

  it "does not run the skipped command" do
    output, error = run_gpush("--skip=rspec")

    expect(error).to be_nil
    expect(output).not_to include("RSPEC-RAN")
    expect(output).to include("BRAKEMAN-RAN")
  end

  it "shows the command as skipped by --skip in the summary" do
    output, = run_gpush("--skip=rspec")

    expect(output).to match(/rspec: .*SKIPPED.* \(by --skip\)/)
  end

  it "matches the name case-insensitively" do
    output, error = run_gpush("--skip", "BRAKEMAN")

    expect(error).to be_nil
    expect(output).not_to include("BRAKEMAN-RAN")
  end

  it "matches the shell of a command with no name" do
    output, error = run_gpush("--skip=echo UNNAMED-RAN")

    expect(error).to be_nil
    expect(output).not_to include("running shell command `echo UNNAMED-RAN`")
  end

  it "skips several commands when repeated, without splitting on commas" do
    config["parallel_run"] << {
      "name" => "lint, fast",
      "shell" => "echo LINT-RAN",
    }

    output, error = run_gpush("--skip=rspec", "--skip=lint, fast")

    expect(error).to be_nil
    expect(output).not_to include("RSPEC-RAN")
    expect(output).not_to include("LINT-RAN")
  end

  it "skips commands in sequential sections without halting" do
    output, error = run_gpush("--skip=setup", "--skip=report")

    expect(error).to be_nil
    expect(output).not_to include("SETUP-RAN")
    expect(output).not_to include("REPORT-RAN")
    expect(output).to include("RSPEC-RAN")
  end

  it "says which checks were skipped at the end of the run" do
    output, = run_gpush("--skip=rspec", "--skip=brakeman")

    expect(output).to include("2 checks skipped: rspec, Brakeman")
  end

  it "says nothing about skipping when nothing was skipped" do
    output, = run_gpush

    expect(output).not_to include("skipped:")
  end

  it "rejects an unknown name before anything runs, listing the names" do
    output, error = run_gpush("--skip=rspek")

    expect(error.message).to eq("Exit called with code 1")
    expect(output).to include("--skip: no command named 'rspek'")
    expect(output).to include("rspec, Brakeman, echo UNNAMED-RAN")
    expect(output).not_to include("SETUP-RAN")
  end

  it "rejects a name that matches more than one command" do
    config["post_run"] << { "name" => "RSpec", "shell" => "echo AGAIN" }

    output, error = run_gpush("--skip=rspec")

    expect(error.message).to eq("Exit called with code 1")
    expect(output).to include("--skip: 'rspec' matches more than one command")
    expect(output).to include("parallel_run: rspec (`echo RSPEC-RAN`)")
    expect(output).to include("post_run: RSpec (`echo AGAIN`)")
    expect(output).not_to include("SETUP-RAN")
  end

  it "says which checks were skipped after a push" do
    allow(GitHelper).to receive(:local_branch_name).and_return("mybranch")
    allow(GitHelper).to receive(:remote_branch_name).and_return(
      "origin/mybranch",
    )
    allow(GitHelper).to receive(:detached_head?).and_return(false)
    allow(GitHelper).to receive(:behind_remote_branch?).and_return(false)
    allow(GitHelper).to receive(
      :up_to_date_or_ahead_of_remote_branch?,
    ).and_return(true)
    allow(GitHelper).to receive(:at_same_commit_as_remote_branch?).and_return(
      false,
    )
    mock_system.add_mock(
      "git push origin HEAD:refs/heads/mybranch",
      output: "",
      exit_code: 0,
    )

    expect { GpushCli.run(%w[--skip=brakeman]) }.to output(
      /Pushed with 1 check skipped: Brakeman/,
    ).to_stdout
  end
end
