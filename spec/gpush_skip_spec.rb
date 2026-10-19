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

  # Lets a non-dry-run get as far as the push
  def allow_a_clean_push
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

  it "matches the name ignoring spaces, dashes and underscores, like gpush run" do
    config["parallel_run"] << {
      "name" => "npm audit",
      "shell" => "echo AUDIT-RAN",
    }

    output, error = run_gpush("--skip=NPM_audit", "--skip= brake-man ")

    expect(error).to be_nil
    expect(output).not_to include("AUDIT-RAN")
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

  it "rejects an unknown name before touching git" do
    expect(GitHelper).not_to receive(:fetch)

    expect { GpushCli.run(%w[--skip=rspek]) }.to raise_error(
      "Exit called with code 1",
    ).and output(/no command named 'rspek'/).to_stdout
  end

  it "rejects an ambiguous name before touching git" do
    config["post_run"] << { "name" => "RSpec", "shell" => "echo AGAIN" }
    expect(GitHelper).not_to receive(:fetch)

    expect { GpushCli.run(%w[--skip=rspec]) }.to raise_error(
      "Exit called with code 1",
    ).and output(/matches more than one command/).to_stdout
  end

  it "only reports commands that were actually skipped" do
    config["post_run_failure"] = [
      { "name" => "notify", "shell" => "echo NOTIFY" },
    ]

    output, error = run_gpush("--skip=notify")

    expect(error).to be_nil
    expect(output).not_to include("skipped: notify")
  end

  it "warns when a name's only commands don't run in this mode" do
    config["parallel_run"] << {
      "name" => "worktree only",
      "shell" => "echo WT",
      "only_worktree" => true,
    }

    output, error = run_gpush("--skip=worktree only")

    expect(error).to be_nil
    expect(output).to include(
      "--skip: 'worktree only' is only on only_worktree commands, and this run isn't in a worktree",
    )
  end

  it "says when a name's commands don't run with --dry-run" do
    config["post_push_success"] = [
      { "name" => "deploy", "shell" => "echo DEPLOY" },
    ]

    output, error = run_gpush("--skip=deploy")

    expect(error).to be_nil
    expect(output).to include(
      "--skip: 'deploy' is only in post_push_success, which doesn't run with --dry-run",
    )
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

  it "only counts commands that run in this mode when matching" do
    config["parallel_run"] = [
      {
        "name" => "rspec",
        "shell" => "echo WORKTREE-RSPEC-RAN",
        "only_worktree" => true,
      },
      {
        "name" => "rspec",
        "shell" => "echo LOCAL-RSPEC-RAN",
        "only_no_worktree" => true,
      },
    ]

    output, error = run_gpush("--skip=rspec")

    expect(error).to be_nil
    expect(output).not_to include(
      "running shell command `echo LOCAL-RSPEC-RAN`",
    )
    expect(output).to include("1 check skipped: rspec")
  end

  it "reports a command with no shell as such, not as a crash" do
    config["post_run"] << { "if" => "true" }

    output, error = run_gpush("--skip=rspec")

    expect(error.message).to eq("Exit called with code 1")
    expect(output).to include('must have a "shell" field')
  end

  it "matches a name that isn't a string" do
    config["parallel_run"] << { "name" => 2024, "shell" => "echo YEAR-RAN" }

    output, error = run_gpush("--skip=2024")

    expect(error).to be_nil
    expect(output).not_to include("running shell command `echo YEAR-RAN`")
  end

  it "allows one name in sections that never both run" do
    config["post_run_success"] = [
      { "name" => "notify", "shell" => "echo PASS-NOTIFY-RAN" },
    ]
    config["post_run_failure"] = [
      { "name" => "notify", "shell" => "echo FAIL-NOTIFY-RAN" },
    ]

    output, error = run_gpush("--skip=notify")

    expect(error).to be_nil
    expect(output).not_to include(
      "running shell command `echo PASS-NOTIFY-RAN`",
    )
    expect(output).to include("1 check skipped: notify")
  end

  it "allows one name in post_run_failure and post_push_success" do
    options = {
      skip: ["notify"],
      post_run_failure: [{ "name" => "notify", "shell" => "echo FAIL-NOTIFY" }],
      post_push_success: [{ "name" => "notify", "shell" => "echo DEPLOY" }],
    }

    expect { SkipHelper.validate_names(options) }.not_to raise_error
  end

  it "still rejects one name in post_run and post_push_success" do
    options = {
      skip: ["notify"],
      post_run: [{ "name" => "notify", "shell" => "echo NOTIFY" }],
      post_push_success: [{ "name" => "notify", "shell" => "echo DEPLOY" }],
    }

    expect { SkipHelper.validate_names(options) }.to raise_error(
      GpushError,
      /matches more than one command/,
    )
  end

  it "lists a command once when it is named twice" do
    output, = run_gpush("--skip=brakeman", "--skip=BRAKEMAN")

    expect(output).to include("1 check skipped: Brakeman")
  end

  it "aborts before anything runs when the config sets skip:" do
    config["skip"] = "brakeman"

    output, error = run_gpush

    expect(error.message).to eq("Exit called with code 1")
    expect(output).to include("'skip' can't be set in the config file")
    expect(output).not_to include("SETUP-RAN")
  end

  it "skips a check that shares its name with a cleanup command" do
    config["cleanup"] = [{ "name" => "rspec", "shell" => "echo CLEANUP-RAN" }]

    output, error = run_gpush("--skip=rspec")

    expect(error).to be_nil
    expect(output).not_to include("running shell command `echo RSPEC-RAN`")
  end

  it "doesn't count post_push commands on a dry run" do
    config["post_run"] << { "name" => "notify", "shell" => "echo NOTIFY-RAN" }
    config["post_push_success"] = [
      { "name" => "notify", "shell" => "echo DEPLOY" },
    ]

    output, error = run_gpush("--skip=notify")

    expect(error).to be_nil
    expect(output).to include("1 check skipped: notify")
  end

  it "judges a name by the run asked for, even if it falls back to a dry run" do
    allow_a_clean_push
    allow(GitHelper).to receive(:at_same_commit_as_remote_branch?).and_return(
      true,
    )
    allow(GitHelper).to receive(:ask_yes_no).and_return(true)
    config["post_run"] << { "name" => "notify", "shell" => "echo NOTIFY-RAN" }
    config["post_push_success"] = [
      { "name" => "notify", "shell" => "echo DEPLOY" },
    ]

    expect { GpushCli.run(%w[--skip=notify]) }.to raise_error(
      "Exit called with code 1",
    ).and output(/matches more than one command/).to_stdout
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
