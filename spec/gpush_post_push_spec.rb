require "spec_helper"
require_relative "../src/ruby/gpush.rb"
require_relative "./mock_system.rb"

RSpec.describe "post_push_success and post_push_failure" do
  let(:mock_system) { MockSystem.new }
  let(:push) { "git push origin HEAD:refs/heads/mybranch" }
  let(:parallel_run) { [{ "name" => "passing check", "shell" => "exit 0" }] }
  let(:post_push_success) do
    [
      {
        "name" => "deploy",
        "shell" =>
          'echo "SUCCESS-RAN sha=$GPUSH_TESTED_SHA branch=$GPUSH_BRANCH"',
        "verbose" => true,
      },
    ]
  end
  let(:post_push_failure) do
    [
      {
        "name" => "say so",
        "shell" =>
          'echo "FAILURE-RAN sha=$GPUSH_TESTED_SHA branch=$GPUSH_BRANCH"',
        "verbose" => true,
      },
    ]
  end

  before do
    Dir.chdir(__dir__)
    GitHelper.instance_variable_set(:@fetch_success, nil)
    allow(GitHelper).to receive(:head_sha).with(short: true).and_return(
      "0123456",
    )
    allow(GitHelper).to receive(:head_sha).with(short: false).and_return(
      "0123456789abcdef0123456789abcdef01234567",
    )
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
    allow(Kernel).to receive(:system) do |*args|
      mock_system.mocked_system_call(
        args.reject { |a| a.is_a?(Hash) }.join(" "),
      )
    end
    allow(Kernel).to receive(:`).and_wrap_original do |_method, *args|
      mock_system.mocked_system_call(args.first)
    end
    allow(YAML).to receive(:load_file).and_return(
      "parallel_run" => parallel_run,
      "post_push_success" => post_push_success,
      "post_push_failure" => post_push_failure,
    )
  end

  around do |example|
    original = ENV.to_h.slice("GPUSH_BRANCH", "GPUSH_TESTED_SHA")
    example.run
  ensure
    ENV.delete("GPUSH_BRANCH")
    ENV.delete("GPUSH_TESTED_SHA")
    ENV.update(original)
  end

  context "when the push succeeds" do
    before { mock_system.add_mock(push, output: "Mock push", exit_code: 0) }

    it "runs post_push_success with the pushed sha and branch" do
      expect { GpushCli.run([]) }.to output(
        /SUCCESS-RAN sha=0123456789abcdef0123456789abcdef01234567 branch=mybranch/,
      ).to_stdout
    end

    it "runs it after the push" do
      output = capture_stdout { GpushCli.run([]) }
      expect(output.index("Mock push")).to be < output.index("SUCCESS-RAN")
    end

    it "does not run post_push_failure" do
      expect { GpushCli.run([]) }.not_to output(/FAILURE-RAN/).to_stdout
    end

    it "leaves GPUSH_TESTED_SHA unset for the rest of the run" do
      capture_stdout { GpushCli.run([]) }
      expect(ENV.fetch("GPUSH_TESTED_SHA", nil)).to be_nil
    end

    context "and a post_push_success command fails" do
      let(:post_push_success) { [{ "name" => "deploy", "shell" => "exit 3" }] }

      it "exits 1, saying the push itself succeeded" do
        expect { GpushCli.run([]) }.to raise_error(
          "Exit called with code 1",
        ).and output(
                /post-push success command failed - deploy.*push itself succeeded/m,
              ).to_stdout
      end

      it "does not congratulate you" do
        expect {
          expect { GpushCli.run([]) }.to raise_error("Exit called with code 1")
        }.not_to output(/Good job/).to_stdout
      end
    end
  end

  context "when the push fails" do
    before do
      mock_system.add_mock(push, output: "! [remote rejected]", exit_code: 1)
    end

    it "runs post_push_failure and still exits 1" do
      expect { GpushCli.run([]) }.to raise_error(
        "Exit called with code 1",
      ).and output(
              /FAILURE-RAN sha=0123456789abcdef0123456789abcdef01234567 branch=mybranch.*git push failed/m,
            ).to_stdout
    end

    it "does not run post_push_success" do
      expect {
        expect { GpushCli.run([]) }.to raise_error("Exit called with code 1")
      }.not_to output(/SUCCESS-RAN/).to_stdout
    end

    context "and a post_push_failure command fails" do
      let(:post_push_failure) { [{ "name" => "say so", "shell" => "exit 3" }] }

      it "still reports that the push failed" do
        expect { GpushCli.run([]) }.to raise_error(
          "Exit called with code 1",
        ).and output(
                /post-push failure command failed - say so.*git push failed/m,
              ).to_stdout
      end
    end
  end

  context "when nothing is pushed" do
    it "runs neither section on a dry run" do
      expect { GpushCli.run(%w[--dry-run]) }.not_to output(
        /SUCCESS-RAN|FAILURE-RAN/,
      ).to_stdout
      expect(mock_system.commands).not_to include(push)
    end

    context "because a check failed" do
      let(:parallel_run) do
        [{ "name" => "failing check", "shell" => "exit 1" }]
      end

      it "runs neither section" do
        expect {
          expect { GpushCli.run([]) }.to raise_error("Exit called with code 1")
        }.not_to output(/SUCCESS-RAN|FAILURE-RAN/).to_stdout
      end
    end
  end

  context "when --set-upstream creates the remote branch" do
    let(:track) { "git branch --set-upstream-to=origin/mybranch mybranch" }

    before do
      allow(GitHelper).to receive(:remote_branch_name).and_return(nil)
      mock_system.add_mock(push, output: "Mock push", exit_code: 0)
    end

    it "counts the push as succeeded even if tracking fails" do
      mock_system.add_mock(track, output: "Mock failed", exit_code: 1)

      expect { GpushCli.run(%w[-u]) }.to output(
        /could not set it as the upstream.*SUCCESS-RAN/m,
      ).to_stdout
    end
  end

  it "does not warn that the new keys are unknown" do
    mock_system.add_mock(push, output: "Mock push", exit_code: 0)

    expect { GpushCli.run([]) }.not_to output(/Unknown config key/).to_stdout
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
