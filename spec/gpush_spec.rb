require "rspec"
require_relative "../src/ruby/gpush.rb"
require_relative "./mock_system.rb"

RSpec.describe "Gpush" do
  let(:mock_system) { MockSystem.new }
  before do
    Dir.chdir(__dir__) # Change to the directory of the current spec file

    allow(Kernel).to receive(:system) do |command|
      mock_system.mocked_system_call(command)
    end
    # Mock all backticks calls globally.
    allow(Kernel).to receive(:`).and_wrap_original do |method, *args|
      mock_system.mocked_system_call(args.first)
    end
  end

  it "finds the gpushrc.yml in the directory" do
    Dir.chdir(File.join(__dir__, "directory_with_config")) do
      expect { go(dry_run: true, verbose: true) }.to output(
        %r{
          Using\ config\ file:\ spec/directory_with_config/gpushrc.yml.*
          Pre-run\ command\ in\ spec/directory_with_config/gpushrc.yml
        }xm,
      ).to_stdout
    end
  end

  it "traverses up the directory tree to find the gpushrc.yml" do
    Dir.chdir(File.join(__dir__, "directory_without_config")) do
      expect { go(dry_run: true, verbose: true) }.to output(
        %r{
          Using\ config\ file:\ spec/gpushrc.yml.*
          Pre-run\ command\ in\ spec/gpushrc.yml
        }xm,
      ).to_stdout
    end
  end

  # xit "runs the pre-defined git push command successfully" do
  #   # Define the mock response for the git push command
  #   mock_system.add_mock("git push", output: "Pushing to origin", exit_code: 0)

  #   # Execute the gpush workflow
  #   expect { go(dry_run: false, verbose: false) }.not_to raise_error

  #   # Validate the command was called
  #   expect(mock_system.commands).to include("git push")
  # end

  # xit "fails when the git push command fails" do
  #   # Define a failing response for git push command
  #   mock_system.add_mock(
  #     "git push",
  #     output: "Error pushing to origin",
  #     exit_code: 1,
  #   )

  #   expect { go(dry_run: false, verbose: false) }.to raise_error(SystemExit)

  #   # Validate the command was called
  #   expect(mock_system.commands).to include("git push")
  # end

  # it "runs successfully with a dry run" do
  #   expect { go(dry_run: true, verbose: false) }.not_to raise_error
  # end
end
