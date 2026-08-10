# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../src/ruby/gpush.rb"

RSpec.describe GpushClaudeReview do
  describe ".build_prompt" do
    it "invokes /code-review with the effort and ref range" do
      prompt =
        described_class.build_prompt(
          "origin/main",
          mode: "code",
          effort: "medium",
          instructions: [],
        )

      expect(prompt).to start_with("/code-review medium origin/main...HEAD")
      expect(prompt).to include("If REVIEW.md exists")
      expect(prompt).to include(described_class::DO_NOT_LINT)
      expect(prompt).to end_with("Nothing should follow the EXIT line.")
    end

    it "invokes /security-review with the effort and ref range" do
      prompt =
        described_class.build_prompt(
          "origin/main",
          mode: "security",
          effort: "medium",
          instructions: [],
        )

      expect(prompt).to start_with(
        "/security-review medium origin/main...HEAD",
      )
      expect(prompt).to include("If SECURITY.md exists")
      expect(prompt).not_to include("REVIEW.md")
      expect(prompt).to end_with("Nothing should follow the EXIT line.")
    end

    it "appends file and text additions in the order given" do
      Dir.mktmpdir do |dir|
        file = File.join(dir, "extra.md")
        File.write(file, "check the schema")

        prompt =
          described_class.build_prompt(
            "origin/main",
            mode: "code",
            effort: "low",
            instructions: [{ text: "first" }, { file: }, { text: "last" }],
          )

        expect(prompt).to start_with("/code-review low origin/main...HEAD")
        expect(prompt).to end_with("first\n\ncheck the schema\n\nlast")
      end
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

    it "rejects an invalid --mode before touching git" do
      expect(YAML).to receive(:load_file).and_return(
        { "gpush_version" => ">=1.0" },
      )
      expect(GpushChangedFiles).not_to receive(:from_options)

      expect { GpushCli.run(%w[claude-review --mode=style]) }.to output(
        /Invalid --mode/,
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
      expect(GpushClaudeAgent).not_to receive(:run)

      expect { GpushCli.run(%w[claude-review --mode=security]) }.to output(
        /Nothing to review/,
      ).to_stdout.and raise_error("Exit called with code 0")
    end
  end
end
