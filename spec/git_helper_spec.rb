# frozen_string_literal: true

require "spec_helper"
require_relative "../src/ruby/git_helper"

RSpec.describe GitHelper do
  describe ".branch_exists_on_origin?" do
    # Stand in for `git ls-remote --heads origin <pattern>`, which matches the
    # pattern against the tail of each ref at slash boundaries -- so the bare
    # pattern "flywheel" also matches "refs/heads/release/flywheel".
    def stub_origin_refs(*refs)
      allow(Open3).to receive(:capture2).with(
        "git",
        "ls-remote",
        "--heads",
        "origin",
        anything,
      ) do |*args|
        pattern = args.last
        matched =
          refs.select { |ref| ref == pattern || ref.end_with?("/#{pattern}") }
        [matched.map { |ref| "#{"a" * 40}\t#{ref}\n" }.join, nil]
      end
    end

    it "is false when only a ref sharing the branch's last segment is on origin" do
      stub_origin_refs("refs/heads/release/flywheel", "refs/heads/main")

      expect(described_class.branch_exists_on_origin?("flywheel")).to be false
    end

    it "is true when the branch itself is on origin" do
      stub_origin_refs("refs/heads/release/flywheel", "refs/heads/flywheel")

      expect(described_class.branch_exists_on_origin?("flywheel")).to be true
    end

    it "is true for a branch whose name contains a slash" do
      stub_origin_refs("refs/heads/release/flywheel")

      expect(
        described_class.branch_exists_on_origin?("release/flywheel"),
      ).to be true
    end

    it "is false when origin has no matching ref" do
      stub_origin_refs("refs/heads/main")

      expect(described_class.branch_exists_on_origin?("flywheel")).to be false
    end
  end

  describe ".ask_yes_no without a terminal" do
    before { allow($stdin).to receive(:tty?).and_return(false) }

    it "uses the default rather than reading stdin" do
      expect($stdin).not_to receive(:getch)

      expect {
        expect(described_class.ask_yes_no("Go?", default: true)).to be true
      }.to output(/Go\? \(no terminal to ask, assuming y\)/).to_stdout
    end

    it "honors a false default" do
      expect(described_class.ask_yes_no("Go?", default: false)).to be false
    end

    it "raises when there is no default, naming the flag to pass" do
      expect($stdin).not_to receive(:getch)

      expect {
        described_class.ask_yes_no("Go?", flag_hint: "Pass -u to answer yes.")
      }.to raise_error(GpushError, /Go\? \(no terminal to ask\) Pass -u/)
    end

    it "raises without a hint when none is given" do
      expect { described_class.ask_yes_no("Go?") }.to raise_error(
        GpushError,
        "Go? (no terminal to ask)",
      )
    end
  end

  describe ".user_wants_to_set_up_remote_branch?" do
    before do
      allow(described_class).to receive(:remote_branch_name).and_return(nil)
      allow($stdin).to receive(:tty?).and_return(false)
    end

    it "points at --set-upstream when it cannot ask" do
      expect { described_class.user_wants_to_set_up_remote_branch? }.to(
        raise_error(GpushError, %r{Pass -u/--set-upstream to answer yes\.}),
      )
    end

    it "does not ask at all with assume_yes" do
      expect(described_class).not_to receive(:ask_yes_no)

      expect(
        described_class.user_wants_to_set_up_remote_branch?(assume_yes: true),
      ).to be true
    end
  end
end
