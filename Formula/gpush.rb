class Gpush < Formula
  desc "Utilities for running linters and tests locally before pushing to a remote git repository"
  homepage "https://github.com/nitidbit/gpush"
  url "https://github.com/username/repo_name/archive/refs/tags/v1.0.0.tar.gz",
      revision: 'be65e6afa9a2cab1998dd3fa04b844bac1911200'
  sha256 "abc123..." # Replace with the correct SHA256 checksum
  license "MIT"

  def install
    bin.install "path/to/gpush_get_specs.rb" => "src/ruby/gpush_get_specs"
    bin.install "path/to/gpush_run_if_any.rb" => "src/ruby/gpush_run_if_any"
    bin.install "path/to/gpush_options_parser.rb" => "src/ruby/gpush_options_parser"
    bin.install "path/to/gpush_changed_files.rb" => "src/ruby/gpush_changed_files"
  end
end
