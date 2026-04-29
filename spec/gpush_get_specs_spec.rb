# frozen_string_literal: true

require "rspec"
require "fileutils"
require "tmpdir"
require_relative "../src/ruby/gpush_get_specs"
require_relative "../src/ruby/git_helper"

RSpec.describe GpushGetSpecs do
  describe "#get_specs" do
    let(:root) { Dir.mktmpdir }
    let(:options) do
      { include_pattern: "spec/**/*_spec.rb", exclude_pattern: }.compact
    end
    let(:exclude_pattern) { nil }

    before do
      FileUtils.mkdir_p File.join(root, "spec")
      FileUtils.touch File.join(root, "spec", "foo_spec.rb")
      FileUtils.touch File.join(root, "spec", "bar_spec.rb")
      allow(GitHelper).to receive(:git_root_dir).and_return(root)
    end

    after { FileUtils.rm_rf(root) }

    subject(:spec_paths) do
      described_class.new(options).send(:get_specs, %w[foo bar])
    end

    context "without exclude_pattern" do
      it "returns spec paths matching keywords from the include glob" do
        expect(spec_paths.map { |p| File.basename(p) }.sort).to eq(%w[bar_spec.rb foo_spec.rb])
      end
    end

    context "with exclude_pattern" do
      let(:exclude_pattern) { "spec/bar_spec.rb" }

      it "omits paths matched by exclude_pattern" do
        expect(spec_paths.map { |p| File.basename(p) }).to eq(["foo_spec.rb"])
      end
    end
  end
end
