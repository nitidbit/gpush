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

    context "with a glob pattern" do
      before do
        allow(Open3).to receive(:capture2).with(
          "git diff --name-only origin/test-branch",
        ).and_return(
          [
            "app/models/user.rb\napp/views/index.html.erb\nlib/task.rake\n",
            double(success?: true),
          ],
        )
      end

      context "with no pattern" do
        it "returns all changed files" do
          files_st = "app/models/user.rb app/views/index.html.erb lib/task.rake"
          expect(subject).to eq files_st
        end
      end

      {
        "*.rb" => "app/models/user.rb", # Matches any .rb file in the current directory
        "**/*.rb" => "app/models/user.rb", # Matches .rb files in any directory
        "**/*.{rb,erb}" => "app/models/user.rb app/views/index.html.erb", # Matches .rb and .erb files recursively
        "**/user.*" => "app/models/user.rb", # Matches files named user.* recursively
        "**/*.rake" => "lib/task.rake", # Matches .rake files recursively
        "app/**/*" => "app/models/user.rb app/views/index.html.erb", # Matches all files under the app directory
        "**/models/*" => "app/models/user.rb", # Matches files directly in the models directory
        "**/*.html.erb" => "app/views/index.html.erb", # Matches files with .html.erb extension
        "lib/**/*" => "lib/task.rake", # Matches all files under the lib directory
      }.each do |pattern, f_str|
        context "with pattern #{pattern}" do
          let(:options) { { pattern: } }
          it("filters correctly") do
            allow(Dir).to receive(:glob).with(pattern).and_return(f_str.split)
            expect(subject).to eq f_str
          end
        end
      end

      context "with multiple glob patterns" do
        let(:options) { { pattern: "*.rb *.rake" } }

        it "raises an error for multiple patterns" do
          expect { subject }.to raise_error(
            GpushError,
            /Invalid pattern: contains spaces/,
          )
        end
      end

      context "with an invalid glob pattern" do
        let(:options) { { pattern: "invalid[pattern" } }

        it "raises an error for invalid pattern" do
          expect { subject }.to raise_error(
            GpushError,
            /Invalid pattern: unmatched/,
          )
        end
      end
    end
  end
end
