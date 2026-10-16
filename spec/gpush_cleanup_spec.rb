require "spec_helper"
require "tmpdir"
require_relative "../src/ruby/gpush.rb"
require_relative "./mock_system.rb"

RSpec.describe "cleanup" do
  let(:mock_system) { MockSystem.new }
  let(:at_exit_hooks) { [] }
  let(:config) do
    {
      "pre_run" => [{ "name" => "setup", "shell" => "echo SETUP-RAN" }],
      "parallel_run" => [{ "name" => "rspec", "shell" => "echo RSPEC-RAN" }],
      "cleanup" => [
        { "name" => "drop db", "shell" => "echo CLEANUP-RAN" },
        {
          "name" => "only in worktree",
          "shell" => "echo WORKTREE-CLEANUP-RAN",
          "only_worktree" => true,
        },
      ],
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
    allow(Notifier).to receive(:notify)
    allow(YAML).to receive(:load_file).and_return(config)
    [Gpush, GpushCleanup].each do |registrar|
      allow(registrar).to receive(:at_exit) { |&hook| at_exit_hooks << hook }
    end
  end

  # Worktree mode exports GPUSH_BRANCH; left set, it decides the diff branch
  # for every example after this one.
  around do |example|
    original = ENV.fetch("GPUSH_BRANCH", nil)
    example.run
  ensure
    ENV["GPUSH_BRANCH"] = original
  end

  # at_exit hooks run in reverse order of registration
  def run_at_exit_hooks = at_exit_hooks.reverse_each(&:call)

  def capture_stdout
    output = StringIO.new
    original_stdout = $stdout
    $stdout = output
    error = nil
    begin
      yield
    rescue RuntimeError => e
      error = e
    ensure
      $stdout = original_stdout
    end
    [output.string, error]
  end

  def run_gpush_and_exit(*args)
    capture_stdout do
      begin
        GpushCli.run(["--dry-run", "-v", *args])
      ensure
        run_at_exit_hooks
      end
    end
  end

  it "runs cleanup after the run" do
    output, error = run_gpush_and_exit

    expect(error).to be_nil
    expect(output.index("CLEANUP-RAN")).to be > output.index("RSPEC-RAN")
  end

  it "does not run cleanup until gpush exits" do
    output, = capture_stdout { GpushCli.run(%w[--dry-run -v]) }

    expect(output).to include("RSPEC-RAN")
    expect(output).not_to include("CLEANUP-RAN")
  end

  it "runs cleanup when a pre_run command fails" do
    config["pre_run"] = [{ "name" => "setup", "shell" => "exit 1" }]

    output, error = run_gpush_and_exit

    expect(error.message).to eq("Exit called with code 1")
    expect(output).to include("CLEANUP-RAN")
  end

  it "filters cleanup commands with only_worktree" do
    output, = run_gpush_and_exit

    expect(output).not_to include("WORKTREE-CLEANUP-RAN")
  end

  it "reports a failing cleanup command, runs the rest, and leaves the exit status alone" do
    config["cleanup"].unshift({ "name" => "broken", "shell" => "exit 3" })

    output, error = run_gpush_and_exit

    expect(error).to be_nil
    expect(output).to include("cleanup command failed - broken")
    expect(output).to include("CLEANUP-RAN")
  end

  it "runs the rest when a cleanup command can't even start" do
    config["cleanup"].unshift(
      { "name" => "missing", "shell" => "gpush-no-such-command" },
    )

    output, error = run_gpush_and_exit

    expect(error).to be_nil
    expect(output).to include("cleanup command failed - missing")
    expect(output).to include("CLEANUP-RAN")
  end

  it "runs the rest when a cleanup command raises" do
    config["cleanup"].unshift(
      { "name" => "bad env", "shell" => "true", "env" => "oops" },
    )

    output, error = run_gpush_and_exit

    expect(error).to be_nil
    expect(output).to include("cleanup command failed - bad env")
    expect(output).to include("CLEANUP-RAN")
  end

  it "reports it, and runs nothing, when the cleanup directory is gone" do
    gone = Dir.mktmpdir("gone", __dir__)
    FileUtils.touch(File.join(gone, "gpushrc.yml"))

    output, error =
      capture_stdout do
        begin
          Dir.chdir(gone) { GpushCli.run(%w[--dry-run -v]) }
        ensure
          FileUtils.rm_rf(gone)
        end
        run_at_exit_hooks
      end

    expect(error).to be_nil
    expect(output).to include("cleanup failed:")
    expect(output).not_to include("CLEANUP-RAN")
  end

  it "rejects a cleanup command with no shell before anything runs" do
    config["cleanup"].unshift({ "name" => "no shell" })

    output, error = run_gpush_and_exit

    expect(error.message).to eq("Exit called with code 1")
    expect(output).to include(
      'cleanup command "no shell" must have a "shell" field',
    )
    expect(output).not_to include("SETUP-RAN")
  end

  it "runs cleanup from the directory gpush ran the checks in" do
    config["cleanup"] = [{ "name" => "where", "shell" => "echo PWD=$(pwd)" }]

    output, =
      capture_stdout do
        GpushCli.run(%w[--dry-run -v])
        Dir.chdir("/")
        run_at_exit_hooks
      end

    expect(output).to include("PWD=#{__dir__}")
  end

  it "stops a hung cleanup command on a second Ctrl-C, then runs the rest" do
    stub_const("InterruptController::STOP_GRACE_SECONDS", 0.3)
    config["cleanup"] = [
      {
        "name" => "hangs",
        "shell" =>
          "trap '' INT; kill -INT $PPID; sleep 0.3; kill -INT $PPID; sleep 30",
      },
      { "name" => "after", "shell" => "echo CLEANUP-RAN" },
    ]

    output, error = run_gpush_and_exit

    expect(error).to be_nil
    expect(output).to include("cleanup command interrupted - hangs")
    expect(output).to include("CLEANUP-RAN")
  end

  it "rejects a cleanup section that isn't a list" do
    config["cleanup"] = { "shell" => "rm -rf tmp" }

    output, error = run_gpush_and_exit

    expect(error.message).to eq("Exit called with code 1")
    expect(output).to include("cleanup must be a list of commands")
  end

  it "ignores Ctrl-C while cleanup runs, then restores the previous handler" do
    config["cleanup"] = [
      {
        "name" => "interrupt",
        "shell" => "kill -INT $PPID; sleep 0.2; echo AFTER-INT",
      },
    ]
    original_handler = Signal.trap("INT", "DEFAULT")
    previous_handler = proc { raise "previous handler called" }
    restored_handler = nil

    begin
      output, error =
        capture_stdout do
          GpushCli.run(%w[--dry-run -v])
          Signal.trap("INT", previous_handler)
          run_at_exit_hooks
          restored_handler = Signal.trap("INT", "DEFAULT")
        end
    ensure
      Signal.trap("INT", original_handler)
    end

    expect(error).to be_nil
    expect(output).not_to include("previous handler called")
    expect(output).to include("AFTER-INT")
    expect(restored_handler).to eq(previous_handler)
  end

  it "runs cleanup in the worktree, before the worktree is removed" do
    config["worktree"] = true
    config["cleanup"] = [{ "name" => "where", "shell" => "echo PWD=$(pwd)" }]
    worktree = File.realpath(Dir.mktmpdir("worktree", __dir__))
    FileUtils.touch(File.join(worktree, "gpushrc.yml"))
    allow(WorktreeHelper).to receive(:create).and_return(worktree)
    allow(WorktreeHelper).to receive(:remove) { puts "WORKTREE-REMOVED" }

    begin
      output, = run_gpush_and_exit
    ensure
      FileUtils.rm_rf(worktree)
    end

    expect(output).to include("PWD=#{worktree}")
    expect(output.index("PWD=")).to be < output.index("WORKTREE-REMOVED")
  end

  it "won't --skip a cleanup command" do
    output, error = run_gpush_and_exit("--skip=drop db")

    expect(error.message).to eq("Exit called with code 1")
    expect(output).to include(
      "--skip: 'drop db' is a cleanup command, which can't be skipped",
    )
    expect(output).not_to include("no command named")
    expect(output).not_to include("SETUP-RAN")
  end
end
