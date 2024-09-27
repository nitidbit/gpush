class Gpush < Formula
  desc "Utilities for running linters and tests locally before pushing to a remote git repository"
  homepage "https://github.com/nitidbit/gpush"
  license "MIT"
  version "local-development"

  EXECUTABLES = [
    "gpush_changed_files.rb",
    "gpush_get_specs.rb",
    "gpush_run_if_any.rb",
    "gpush.rb",
  ]

  OTHER_FILES = [
    "../../gpushrc_default.yml"
  ]

  # Use local path as the source for the formula
  url "file://#{Pathname.new(File.expand_path(__dir__)).parent}/src/ruby"

  def install
    source_path = Pathname.new(File.expand_path(__dir__)).parent/"src/ruby"

    # Logging the start of the installation process
    ohai "Starting installation of gpush"

    # Ensure libexec directory exists
    libexec.mkpath

    # Copy all Ruby scripts (*.rb) to the libexec directory
    ohai "Copying all Ruby scripts to the libexec directory"
    Dir.glob(source_path/"*.rb").each do |file|
      cp file, libexec
    end

    OTHER_FILES.each do |file|
      cp File.join(source_path, file), libexec
    end

    # Set execute permissions on the command files only
    ohai "Making command files executable"
    EXECUTABLES.each do |file|
      chmod "+x", libexec/file

      # Create wrapper scripts for each command file
      bin_name = File.basename(file, ".rb") # Get the name without the .rb extension
      (bin/bin_name).write <<~EOS
        #!/bin/bash
        exec ruby "#{libexec}/#{file}" "$@"
      EOS
      chmod "+x", bin/bin_name
    end

    # Confirming the installation
    ohai "gpush installation completed"
  end

  test do
    # Test to ensure the command runs successfully
    system "#{bin}/gpush", "--version"
  end
end
