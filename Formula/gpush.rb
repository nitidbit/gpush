class Gpush < Formula
  desc "Utilities for running linters and tests locally before pushing to a remote git repository"
  homepage "https://github.com/nitidbit/gpush"
  url "https://github.com/nitidbit/gpush.git",
      using:    :git,
      revision: "314a12e0690b6e5d3ff8a0f9bceffd6e33427407"
  license "MIT"
  version "0.0.0"

  depends_on "python@3.12"

  def install
    # Logging the start of the installation process
    ohai "Starting installation of gpush"

    # Install the Ruby scripts to the bin directory
    ohai "Installing Ruby scripts to the bin directory"
    bin.install "src/ruby/gpush_get_specs.rb" => "gpush_get_specs"
    bin.install "src/ruby/gpush_run_if_any.rb" => "gpush_run_if_any"
    bin.install "src/ruby/gpush_options_parser.rb" => "gpush_options_parser"
    bin.install "src/ruby/gpush_changed_files.rb" => "gpush_changed_files"

    # Install the Python package directly to the Homebrew site-packages
    ohai "Installing the Python package using pip"
    system "pip3", "install", "--prefix=#{prefix}", "git+https://github.com/nitidbit/gpush.git@release/v2-hackathon"

    # Create a wrapper script to run the gpush Python command
    (bin/"gpush").write <<~EOS
      #!/bin/bash
      python3 -m gpush "$@"
    EOS

    # Set execute permissions on the wrapper script
    chmod "+x", bin/"gpush"

    # Confirming the installation
    ohai "gpush installation completed"
  end

  # test do
  #   # Test to ensure the command runs successfully
  #   system "#{bin}/gpush", "--version"
  # end
end
