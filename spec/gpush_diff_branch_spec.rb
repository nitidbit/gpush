require "spec_helper"
require_relative "../src/ruby/gpush.rb"

RSpec.describe "gpush diff-branch" do
  before { Dir.chdir(__dir__) }

  it "prints origin/<branch> and exits 0" do
    expect(YAML).to receive(:load_file).and_return(
      { "gpush_version" => ">=1.0" },
    )
    expect(GitHelper).to receive(:local_branch_name).and_return("mybranch")
    expect(GitHelper).to receive(:branch_exists_on_origin?).with(
      "mybranch",
    ).and_return(true)

    expect { GpushCli.run(%w[diff-branch]) }.to output(
      "origin/mybranch\n",
    ).to_stdout.and raise_error("Exit called with code 0")
  end

  it "falls back to origin/main when origin only has a ref sharing the branch's last segment" do
    expect(YAML).to receive(:load_file).and_return(
      { "gpush_version" => ">=1.0" },
    )
    allow(GitHelper).to receive(:local_branch_name).and_return("flywheel")
    # Only the git subprocess is stubbed here, so branch resolution runs for real.
    allow(Open3).to receive(:capture2).and_call_original
    allow(Open3).to receive(:capture2).with(
      "git",
      "ls-remote",
      "--heads",
      "origin",
      anything,
    ) do |*args|
      pattern = args.last
      matched =
        %w[refs/heads/release/flywheel refs/heads/main].select do |ref|
          ref == pattern || ref.end_with?("/#{pattern}")
        end
      [matched.map { |ref| "#{"a" * 40}\t#{ref}\n" }.join, nil]
    end

    expect { GpushCli.run(%w[diff-branch]) }.to output(
      "origin/main\n",
    ).to_stdout.and raise_error("Exit called with code 0")
  end

  it "rejects extra arguments" do
    expect(YAML).to receive(:load_file).and_return(
      { "gpush_version" => ">=1.0" },
    )

    expect { GpushCli.run(%w[diff-branch extra]) }.to output(
      /Unexpected argument/,
    ).to_stdout.and raise_error("Exit called with code 1")
  end
end
