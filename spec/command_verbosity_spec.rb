require "rspec"
require_relative "../src/ruby/gpush.rb"
require_relative "./mock_system.rb"

RSpec.describe "Command Verbosity" do
  let(:mock_system) { MockSystem.new }
  let(:test_config) do
    {
      "post_run_success" => [
        {
          "name" => "verbose command",
          "shell" => "echo 'verbose output'",
          "verbose" => true,
        },
        {
          "name" => "quiet command",
          "shell" => "echo 'quiet output'",
          "verbose" => false,
        },
        { "name" => "default command", "shell" => "echo 'default output'" },
      ],
    }
  end

  before do
    Dir.chdir(__dir__)
    allow(Kernel).to receive(:system) do |command|
      mock_system.mocked_system_call(command)
    end
    allow(Kernel).to receive(:`) do |command|
      mock_system.mocked_system_call(command)
    end
    expect(YAML).to receive(:load_file).exactly(:once).and_return(test_config)
  end

  it "runs verbose commands with full output regardless of global verbose setting" do
    mock_system.add_mock(
      "echo 'verbose output'",
      output: "verbose output",
      exit_code: 0,
    )
    expect { Gpush.cl(%w[--dry-run --verbose]) }.to output(
      /Running post-run success.*verbose output.*post-run success DONE/m,
    ).to_stdout
  end

  it "runs quiet commands without output regardless of global verbose setting" do
    mock_system.add_mock(
      "echo 'quiet output'",
      output: "quiet output",
      exit_code: 0,
    )

    expect { Gpush.cl(%w[--dry-run --verbose]) }.not_to output(
      /quiet output/,
    ).to_stdout
  end

  context "runs default commands according to global verbose setting" do
    before do
      mock_system.add_mock(
        "echo 'default output'",
        output: "default output",
        exit_code: 0,
      )
    end

    it "when CLI does not specify verbose" do
      expect { Gpush.cl(%w[--dry-run]) }.not_to output(
        /default output/,
      ).to_stdout
    end

    it "when CLI specifies verbose" do
      expect { Gpush.cl(%w[--dry-run --verbose]) }.to output(
        /default output/,
      ).to_stdout
    end
  end

  it "shows section title when any command in the section is verbose" do
    mock_system.add_mock(
      "echo 'verbose output'",
      output: "verbose output",
      exit_code: 0,
    )
    mock_system.add_mock(
      "echo 'quiet output'",
      output: "quiet output",
      exit_code: 0,
    )
    mock_system.add_mock(
      "echo 'default output'",
      output: "default output",
      exit_code: 0,
    )

    expect { Gpush.cl(%w[--dry-run]) }.to output(
      /Running post-run success.*post-run success DONE/m,
    ).to_stdout
  end
end
