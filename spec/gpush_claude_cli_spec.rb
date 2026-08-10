# frozen_string_literal: true

require "spec_helper"
require_relative "../src/ruby/gpush.rb"

RSpec.describe GpushClaudeCli do
  describe ".check_version!" do
    subject(:check!) { described_class.check_version!("2.1.1") }

    def stub_version(stdout, success: true)
      allow(Open3).to receive(:capture3).with("claude", "--version").and_return(
        [stdout, "", double(success?: success, exitstatus: success ? 0 : 1)],
      )
    end

    it "accepts a version at or above the minimum" do
      stub_version("2.1.1 (Claude Code)")
      expect { check! }.not_to raise_error

      stub_version("2.1.223 (Claude Code)")
      expect { check! }.not_to raise_error
    end

    it "rejects a version below the minimum, naming the version found" do
      stub_version("2.0.9 (Claude Code)")

      expect { check! }.to raise_error(GpushError, /2\.0\.9 is too old/)
    end

    it "compares numerically, not as strings" do
      # "10.0.0" sorts BELOW "2.1.1" as a string, so a naive compare would
      # reject a CLI that is years newer than the minimum.
      stub_version("10.0.0 (Claude Code)")

      expect { check! }.not_to raise_error
    end

    it "reports the minimum it was given" do
      stub_version("2.1.1 (Claude Code)")

      expect { described_class.check_version!("3.0.0") }.to raise_error(
        GpushError,
        /need 3\.0\.0 or newer/,
      )
    end

    it "raises a friendly error when the claude CLI is not on PATH" do
      allow(Open3).to receive(:capture3).with("claude", "--version").and_raise(
        Errno::ENOENT,
      )

      expect { check! }.to raise_error(GpushError, /not found on PATH/)
    end

    it "raises when the version output is unparseable" do
      stub_version("who knows")

      expect { check! }.to raise_error(GpushError, /Could not read a version/)
    end

    it "raises when the command exits non-zero" do
      stub_version("", success: false)

      expect { check! }.to raise_error(GpushError, /`claude --version` failed/)
    end
  end

  describe ".check_auth!" do
    subject(:check!) { described_class.check_auth! }

    def stub_auth(stdout, stderr = "", **status)
      allow(Open3).to receive(:capture3).with(
        "claude",
        "auth",
        "status",
      ).and_return([stdout, stderr, double(success?: true, **status)])
    end

    it "does not raise when logged in" do
      stub_auth(%({"loggedIn": true, "email": "a@b.com"}))

      expect { check! }.not_to raise_error
    end

    it "raises with a login hint when not logged in" do
      stub_auth(%({"loggedIn": false}))

      expect { check! }.to raise_error(GpushError, /Run `claude auth login`/)
    end

    it "raises a friendly error when the claude CLI is not on PATH" do
      allow(Open3).to receive(:capture3).with(
        "claude",
        "auth",
        "status",
      ).and_raise(Errno::ENOENT)

      expect { check! }.to raise_error(GpushError, /not found on PATH/)
    end

    it "raises when the command exits non-zero, naming the subcommand" do
      allow(Open3).to receive(:capture3).with(
        "claude",
        "auth",
        "status",
      ).and_return(
        ["", "command not found", double(success?: false, exitstatus: 127)],
      )

      expect { check! }.to raise_error(
        GpushError,
        /claude auth status.*failed \(exit 127\).*command not found/m,
      )
    end

    it "raises when the output is not JSON" do
      stub_auth("not json")

      expect { check! }.to raise_error(
        GpushError,
        /Unexpected output from `claude auth status`/,
      )
    end
  end
end
