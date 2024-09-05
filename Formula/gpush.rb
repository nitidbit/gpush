class Gpush < Formula
  desc "Utilities for running linters and tests locally before pushing to a remote git repository"
  homepage "https://github.com/nitidbit/gpush"
  url "https://github.com/nitidbit/gpush.git",
      using:    :git,
      revision: "b71e0a55ac52547946828bbfb5be9c8f4613bc22"
  license "MIT"
  version '2.0.0-alpha.3'

  depends_on "python@3.12"

  RUBY_SCRIPTS = %w[
    gpush_get_specs.rb
    gpush_run_if_any.rb
    gpush_options_parser.rb
    gpush_changed_files.rb
  ].freeze

  def install
    # Logging the start of the installation process
    ohai "Starting installation of gpush"

    # Install the Ruby scripts to the libexec directory
    ohai "Installing Ruby scripts to the libexec directory"
    libexec.install RUBY_SCRIPTS.map { |script| "src/ruby/#{script}" }

    # Set execute permissions on the Ruby scripts and create symlinks
    RUBY_SCRIPTS.each do |script|
      chmod "+x", libexec/script
      bin.install_symlink libexec/script => script.sub(".rb", "")
    end

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
