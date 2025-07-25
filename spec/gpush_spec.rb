require "spec_helper"
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
    Dir.chdir(File.join(__dir__, "directory_with_config"))

    expect { Gpush.cl(%w[--dry-run --verbose]) }.to output(
      %r{
        Using\ config\ file:\ spec/directory_with_config/gpushrc.yml.*
        Pre-run\ command\ in\ spec/directory_with_config/gpushrc.yml
      }xm,
    ).to_stdout
  end

  it "traverses up the directory tree to find the gpushrc.yml" do
    Dir.chdir(File.join(__dir__, "directory_without_config"))
    expect { Gpush.cl(%w[--dry-run --verbose]) }.to output(
      %r{
        Using\ config\ file:\ spec/gpushrc.yml.*
        Pre-run\ command\ in\ spec/gpushrc.yml
      }xm,
    ).to_stdout
  end

  it "runs the commands from directory of the gpushrc.yml" do
    Dir.chdir(File.join(__dir__, "directory_with_config", "empty_subdir"))
    expect { Gpush.cl(%w[--dry-run --verbose]) }.to output(
      /#{Regexp.escape("Current directory in braces: [#{__dir__}/directory_with_config]")}/xm,
    ).to_stdout
  end

  it "accepts a custom config file" do
    expect {
      Gpush.cl(%w[--dry-run --verbose --config-file=gpush_alt_config.yml])
    }.to output(
      /#{Regexp.escape("Using config file: spec/gpush_alt_config.yml")}/xm,
    ).to_stdout
  end

  it "complains if the custom config file does not exist" do
    expect {
      Gpush.cl(%w[--dry-run --verbose --config-file=non_existent.yml])
    }.to raise_error("Exit called with code 1").and output(
            /#{Regexp.escape("Config file not found: non_existent.yml")}/m,
          ).to_stdout
  end

  it "can print the version" do
    stub_const("VERSION", "42.0.0")
    expect { Gpush.cl(%w[--version]) }.to output(
      /gpush 42.0.0/,
    ).to_stdout.and raise_error("Exit called with code 0")
  end

  context "version check" do
    before { stub_const("VERSION", "2.0.0") }

    it "aborts if gpush_version in the config file is not compatible" do
      expect(YAML).to receive(:load_file).exactly(:once).and_return(
        "gpush_version" => ">50.0",
      )
      expect { Gpush.cl(%w[--dry-run --verbose]) }.to raise_error(
        "Exit called with code 1",
      ).and output(
              /#{Regexp.escape("Your config file specifies version >50.0. You have 2.0.0.")}\n\n#{Regexp.escape("Run 'brew update && brew upgrade gpush' to update.")}/m,
            ).to_stdout
    end

    it "proceeds if gpush_version in the config file is compatible" do
      expect(YAML).to receive(:load_file).exactly(:once).and_return(
        "gpush_version" => %w[<50.0 >1.1.0],
      )
      expect { Gpush.cl(%w[--dry-run --verbose]) }.to output(
        /#{Regexp.escape "《 Dry run completed 》"}/xm,
      ).to_stdout
    end
  end

  context "success emoji" do
    before do
      expect(YAML).to receive(:load_file).exactly(:once).and_return(
        "success_emoji" => "🦄",
      )
    end
    it "prints it when not in dry run mode" do
      expect(GitHelper).to receive(:behind_remote_branch?).and_return(false)
      expect(GitHelper).to receive(
        :up_to_date_or_ahead_of_remote_branch?,
      ).and_return(true)
      expect(GitHelper).to receive(
        :at_same_commit_as_remote_branch?,
      ).and_return(false)
      mock_system.add_mock(
        "git push",
        output: "Mock pushing to origin",
        exit_code: 0,
      )
      expect { Gpush.cl([]) }.to output(/#{Regexp.escape "🦄"}/xm).to_stdout
    end

    it "does not print it when in dry run mode" do
      expect { Gpush.cl(%w[--dry-run]) }.not_to output(
        /#{Regexp.escape "🦄"}/xm,
      ).to_stdout
    end
  end

  # xit "runs the pre-defined git push command successfully" do
  #   # Define the mock response for the git push command
  #   mock_system.add_mock("git push", output: "Pushing to origin", exit_code: 0)

  #   # Execute the gpush workflow
  #   expect { Gpush.go(dry_run: false, verbose: false) }.not_to raise_error

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

  #   expect { Gpush.go(dry_run: false, verbose: false) }.to raise_error(SystemExit)

  #   # Validate the command was called
  #   expect(mock_system.commands).to include("git push")
  # end

  # it "runs successfully with a dry run" do
  #   expect { Gpush.go(dry_run: true, verbose: false) }.not_to raise_error
  # end
end
