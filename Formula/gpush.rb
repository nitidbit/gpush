class Gpush < Formula
  desc "Utilities for running linters and tests locally before pushing to a remote git repository"
  homepage "https://github.com/nitidbit/gpush"
  license "MIT"
  version "2.0.0-alpha.4"

  # Use local path as the source for the formula
  url "file://#{Pathname.new(File.expand_path(__dir__)).parent}/src/ruby"

  def install
    source_path = Pathname.new(File.expand_path(__dir__)).parent/"src/ruby"

    # Logging the start of the installation process
    ohai "Starting installation of gpush"

    # Ensure libexec directory exists
    libexec.mkpath

    # Copy Ruby scripts to the libexec directory
    ohai "Copying Ruby scripts to the libexec directory"
    Dir[source_path/"*.rb"].each do |script|
      cp script, libexec
      chmod "+x", libexec/"#{File.basename(script)}"
    end

    # Create a wrapper script to run the gpush Ruby command
    (bin/"gpush").write <<~EOS
      #!/bin/bash
      exec ruby "#{libexec}/gpush.rb" "$@"
    EOS

    # Set execute permissions on the wrapper script
    chmod "+x", bin/"gpush"

    # Confirming the installation
    ohai "gpush installation completed"
  end

  test do
    # Test to ensure the command runs successfully
    system "#{bin}/gpush", "--version"
  end
end
