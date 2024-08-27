class Gpush < Formula
  desc "Utilities for running linters and tests locally before pushing to a remote git repository"
  homepage "https://github.com/nitidbit/gpush"
  url "https://github.com/nitidbit/gpush.git",
      using:    :git,
      revision: "314a12e0690b6e5d3ff8a0f9bceffd6e33427407"
  license "MIT"
  version "0.0.0"

  depends_on "python@3.12"
  depends_on "pipx"

  def install
    # Logging the start of the installation process
    ohai "Starting installation of gpush"

    # Install the Ruby scripts to the bin directory
    ohai "Installing Ruby scripts to the bin directory"
    bin.install "src/ruby/gpush_get_specs.rb" => "gpush_get_specs"
    bin.install "src/ruby/gpush_run_if_any.rb" => "gpush_run_if_any"
    bin.install "src/ruby/gpush_options_parser.rb" => "gpush_options_parser"
    bin.install "src/ruby/gpush_changed_files.rb" => "gpush_changed_files"

    # Install the Python package using pipx
    ohai "Installing the Python package using pipx"
    system "pipx", "install", "git+https://github.com/nitidbit/gpush.git@894b5598253639abbbce31bd25ec39ff6a5a6b0e"

    # Assuming pipx installed the gpush binary in the standard location
    pipx_bin_path = "#{ENV['HOME']}/.local/pipx/venvs/gpush/bin/gpush"
    if File.exist?(pipx_bin_path)
      ohai "Found gpush binary at #{pipx_bin_path}, creating symlink in Homebrew bin directory"
      bin.install_symlink pipx_bin_path => "gpush"
    else
      odie "Failed to locate gpush binary installed by pipx at #{pipx_bin_path}"
    end

    # Confirming the installation
    ohai "gpush installation completed"
  end
end
