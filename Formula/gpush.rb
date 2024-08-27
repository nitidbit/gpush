class Gpush < Formula
  desc "Utilities for running linters and tests locally before pushing to a remote git repository"
  homepage "https://github.com/nitidbit/gpush"
  url "https://github.com/nitidbit/gpush.git",
      using:    :git,
      revision: "314a12e0690b6e5d3ff8a0f9bceffd6e33427407"
  license "MIT"
  version "0.0.0"

  depends_on "python@3.12"
  depends_on "pipx"  # Add pipx as a dependency if you're using it

  def install
    # Install the Ruby scripts to the bin directory
    bin.install "src/ruby/gpush_get_specs.rb" => "gpush_get_specs"
    bin.install "src/ruby/gpush_run_if_any.rb" => "gpush_run_if_any"
    bin.install "src/ruby/gpush_options_parser.rb" => "gpush_options_parser"
    bin.install "src/ruby/gpush_changed_files.rb" => "gpush_changed_files"

    # Install the Python package using pip in the user space
    system "python3", "-m", "pip", "install", "--user", "git+https://github.com/nitidbit/gpush/commit/894b5598253639abbbce31bd25ec39ff6a5a6b0e"

    # Ensure the installed Python scripts are linked
    python_user_base = `python3 -m site --user-base`.chomp
    python_bin_dir = "#{python_user_base}/bin"
    bin.install_symlink "#{python_bin_dir}/gpush" => "gpush"
  end
end
