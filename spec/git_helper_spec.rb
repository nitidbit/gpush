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
end
