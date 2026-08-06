# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../src/ruby/gpush.rb"

RSpec.describe GpushClaudeReview do
  describe ".build_prompt" do
    it "invokes /code-review with the effort and ref range, no additions" do
      prompt = described_class.build_prompt("origin/main", "medium", [])

      expect(prompt).to start_with("/code-review medium origin/main...HEAD")
      expect(prompt).to end_with("Nothing should follow the EXIT line.")
    end

    it "appends file and text additions in the order given" do
      Dir.mktmpdir do |dir|
        file = File.join(dir, "extra.md")
        File.write(file, "check the schema")

        prompt =
          described_class.build_prompt(
            "origin/main",
            "low",
            [{ text: "first" }, { file: }, { text: "last" }],
          )

        expect(prompt).to start_with("/code-review low origin/main...HEAD")
        expect(prompt).to end_with("first\n\ncheck the schema\n\nlast")
      end
    end

    it "raises when an instructions file is missing" do
      expect {
        described_class.build_prompt(
          "origin/main",
          "medium",
          [{ file: "no_such_file.md" }],
        )
      }.to raise_error(GpushError, /Instructions file not found/)
    end
  end

  describe ".exit_code_from" do
    it "maps the EXIT line to an exit code" do
      expect(described_class.exit_code_from("review text\nEXIT 0\n")).to eq 0
      expect(described_class.exit_code_from("findings...\nEXIT 1\n")).to eq 1
      expect(described_class.exit_code_from("EXIT 2")).to eq 2
    end

    it "ignores a trailing code fence and blank lines after the EXIT line" do
      expect(described_class.exit_code_from("review\nEXIT 1\n```\n")).to eq 1
      expect(
        described_class.exit_code_from("review\nEXIT 0\n\n```\n\n"),
      ).to eq 0
    end

    it "returns 3 and warns when the exit line is malformed" do
      code = nil
      expect {
        code = described_class.exit_code_from("looks good!\n")
      }.to output(/did not produce a valid exit code/).to_stderr
      expect(code).to eq 3
    end
  end

  describe ".claude_command" do
    subject(:command) { described_class.send(:claude_command) }

    # Security-relevant: --allowedTools is additive on top of the developer's
    # settings files, so without --setting-sources "" the review inherits their
    # allow rules and can run anything they have ever approved.
    it "loads no setting sources, so no local permissions are inherited" do
      expect(command).to include("--setting-sources")
      expect(command[command.index("--setting-sources") + 1]).to eq ""
    end

    it "grants only the read-only git commands" do
      expect(command[command.index("--allowedTools") + 1]).to eq(
        "Bash(git diff*),Bash(git log*),Bash(git show*)",
      )
    end
  end

  describe ".claude_command with extra tools" do
    it "appends a project's --allowed-tools after the defaults" do
      command =
        described_class.send(
          :claude_command,
          ["Bash(bundle exec rubocop*)", "Bash(bin/tsc*)"],
        )

      expect(command[command.index("--allowedTools") + 1]).to eq(
        "Bash(git diff*),Bash(git log*),Bash(git show*)," \
          "Bash(bundle exec rubocop*),Bash(bin/tsc*)",
      )
    end

    it "still loads no setting sources when tools are added" do
      command = described_class.send(:claude_command, ["Bash(anything*)"])

      expect(command[command.index("--setting-sources") + 1]).to eq ""
    end
  end

  describe "running via the CLI" do
    before { Dir.chdir(__dir__) }

    it "rejects extra arguments" do
      expect(YAML).to receive(:load_file).and_return(
        { "gpush_version" => ">=1.0" },
      )

      expect { GpushCli.run(%w[claude-review extra]) }.to output(
        /Unexpected argument/,
      ).to_stdout.and raise_error("Exit called with code 1")
    end

    it "rejects an invalid --effort level before touching git" do
      expect(YAML).to receive(:load_file).and_return(
        { "gpush_version" => ">=1.0" },
      )
      expect(GpushChangedFiles).not_to receive(:from_options)

      expect { GpushCli.run(%w[claude-review --effort=turbo]) }.to output(
        /Invalid --effort/,
      ).to_stdout.and raise_error("Exit called with code 1")
    end

    it "exits 0 without running claude when there is nothing to review" do
      expect(YAML).to receive(:load_file).and_return(
        { "gpush_version" => ">=1.0" },
      )
      allow(GitHelper).to receive(:local_branch_name).and_return("mybranch")
      allow(GitHelper).to receive(:branch_exists_on_origin?).and_return(true)
      allow(Open3).to receive(:capture2).with(
        "git diff --name-only origin/mybranch",
      ).and_return(["", double(success?: true)])
      expect(described_class).not_to receive(:run_review)

      expect { GpushCli.run(%w[claude-review]) }.to output(
        /Nothing to review/,
      ).to_stdout.and raise_error("Exit called with code 0")
    end
  end
end
