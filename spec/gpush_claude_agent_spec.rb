# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../src/ruby/gpush.rb"

RSpec.describe GpushClaudeAgent do
  describe ".build_prompt" do
    it "assembles lead, guidance file, extras, EXIT block, then additions" do
      Dir.mktmpdir do |dir|
        file = File.join(dir, "extra.md")
        File.write(file, "check the schema")

        prompt =
          described_class.build_prompt(
            lead: "/code-review medium origin/main...HEAD",
            guidance_file: "REVIEW.md",
            instructions: [{ text: "first" }, { file: }, { text: "last" }],
            extra_sections: ["extra skill notes"],
          )

        expect(prompt).to start_with("/code-review medium origin/main...HEAD")
        expect(prompt).to include("If REVIEW.md exists")
        expect(prompt).to include("extra skill notes")
        expect(prompt).to include(described_class::EXIT_INSTRUCTIONS)
        expect(prompt).to end_with("first\n\ncheck the schema\n\nlast")
      end
    end

    it "raises when an instructions file is missing" do
      expect {
        described_class.build_prompt(
          lead: "/security-review origin/main...HEAD",
          guidance_file: "SECURITY.md",
          instructions: [{ file: "no_such_file.md" }],
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
    subject(:command) do
      described_class.claude_command(
        allowed_tools: described_class::DEFAULT_ALLOWED_TOOLS,
      )
    end

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
        described_class.claude_command(
          allowed_tools: described_class::DEFAULT_ALLOWED_TOOLS,
          extra_tools: ["Bash(bundle exec rubocop*)", "Bash(bin/tsc*)"],
        )

      expect(command[command.index("--allowedTools") + 1]).to eq(
        "Bash(git diff*),Bash(git log*),Bash(git show*)," \
          "Bash(bundle exec rubocop*),Bash(bin/tsc*)",
      )
    end

    it "still loads no setting sources when tools are added" do
      command =
        described_class.claude_command(
          allowed_tools: described_class::DEFAULT_ALLOWED_TOOLS,
          extra_tools: ["Bash(anything*)"],
        )

      expect(command[command.index("--setting-sources") + 1]).to eq ""
    end
  end
end
