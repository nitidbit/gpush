require "rspec"
require_relative "../src/ruby/gpush_changed_files.rb"

RSpec.describe "gpush_changed_files" do
  let(:options) { {} }
  subject { GpushChangedFiles.new(options).format_changed_files }

  before { Dir.chdir(__dir__) } # Change to the directory of the current spec file

  context "when the branch exists on origin" do
    before do
      expect(GitHelper).to receive(:local_branch_name).and_return("test-branch")
      expect(GitHelper).to receive(:branch_exists_on_origin?).and_return(true)
      expect(GitHelper).to receive(:git_root_dir).and_return(__dir__)
      allow(File).to receive(:exist?) do |filename|
        !filename.include?("deleted")
      end
    end

    context "where one or more files have been deleted" do
      before do
        allow(Open3).to receive(:capture2).with(
          "git diff --name-only origin/test-branch",
        ).and_return(
          ["extant_file.rb\ndeleted_file.rb\n", double(success?: true)],
        )
      end

      it "does not include deleted files by default" do
        expect(subject).to eq "extant_file.rb"
      end
      context "with option include_deleted_files" do
        let(:options) { { include_deleted_files: true } }

        it "includes deleted files" do
          expect(subject).to eq "extant_file.rb deleted_file.rb"
        end
      end
    end
  end
end
