require "spec_helper"
require_relative "../src/ruby/gpush.rb"
require_relative "./mock_system.rb"

# ExitHelper.exit is stubbed in spec_helper to raise "Exit called with code N",
# so these examples assert on the code gpush hands back to the shell.
RSpec.describe "exit codes" do
  let(:mock_system) { MockSystem.new }

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

  # Lets a non-dry-run reach the push step
  def allow_a_clean_push(branch: "mybranch")
    allow(GitHelper).to receive(:local_branch_name).and_return(branch)
    allow(GitHelper).to receive(:remote_branch_name).and_return(
      "origin/#{branch}",
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

  context "when a parallel_run command fails" do
    before do
      allow(YAML).to receive(:load_file).and_return(
        "parallel_run" => [{ "name" => "failing check", "shell" => "exit 1" }],
      )
    end

    it "exits 1" do
      expect { GpushCli.run(%w[--dry-run]) }.to raise_error(
        "Exit called with code 1",
      ).and output(/Errors detected/).to_stdout
    end
  end

  context "when git push fails" do
    before do
      allow(YAML).to receive(:load_file).and_return(
        "parallel_run" => [{ "name" => "passing check", "shell" => "exit 0" }],
      )
      allow_a_clean_push
      mock_system.add_mock(
        "git push origin HEAD:mybranch",
        output: "! [remote rejected]",
        exit_code: 1,
      )
    end

    it "exits 1 instead of congratulating you" do
      expect { GpushCli.run([]) }.to raise_error(
        "Exit called with code 1",
      ).and output(/git push failed/).to_stdout
    end

    it "does not print the success emoji" do
      expect {
        expect { GpushCli.run([]) }.to raise_error("Exit called with code 1")
      }.not_to output(/Good job/).to_stdout
    end
  end

  context "git state we cannot work with" do
    before do
      allow(YAML).to receive(:load_file).and_return(
        "parallel_run" => [{ "name" => "passing check", "shell" => "exit 0" }],
      )
    end

    it "exits 1 when not in a git repository" do
      allow(GitHelper).to receive(:not_a_git_repository?).and_return(true)
      expect { GpushCli.run(%w[--dry-run]) }.to raise_error(
        "Exit called with code 1",
      ).and output(/Not inside a Git repository/).to_stdout
    end

    it "exits 1 when git fetch fails" do
      allow(GitHelper).to receive(:not_a_git_repository?).and_return(false)
      allow(GitHelper).to receive(:fetch).and_return(false)
      expect { GpushCli.run([]) }.to raise_error(
        "Exit called with code 1",
      ).and output(/git fetch failed/).to_stdout
    end

    it "exits 1 when the local branch is behind the remote" do
      allow_a_clean_push
      allow(GitHelper).to receive(
        :up_to_date_or_ahead_of_remote_branch?,
      ).and_return(false)
      expect { GpushCli.run([]) }.to raise_error(
        "Exit called with code 1",
      ).and output(/not up to date with the remote branch/).to_stdout
    end

    it "exits 0 when the user declines to run tests anyway" do
      allow(GitHelper).to receive(:detached_head?).and_return(true)
      allow(GitHelper).to receive(:ask_yes_no).and_return(false)
      expect { GpushCli.run([]) }.not_to raise_error
    end
  end

  it "exits 0 for --help" do
    expect { GpushCli.run(%w[--help]) }.to raise_error(
      "Exit called with code 0",
    ).and output(/Usage:/).to_stdout
  end

  it "exits 0 on a successful dry run" do
    allow(YAML).to receive(:load_file).and_return(
      "parallel_run" => [{ "name" => "passing check", "shell" => "exit 0" }],
    )
    expect { GpushCli.run(%w[--dry-run]) }.not_to raise_error
  end
end
