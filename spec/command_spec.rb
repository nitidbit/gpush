require "spec_helper"
require_relative "../src/ruby/gpush.rb"

RSpec.describe Command do
  before { Dir.chdir(__dir__) }

  def run_quietly(command)
    expect { command.run }.to output.to_stdout
    command
  end

  it "reports a command killed by a signal it wasn't sent as failed, with its output" do
    command =
      Command.new(
        { "name" => "crashes", "shell" => "echo BOOM; kill -KILL $$" },
      )

    expect { command.run }.to output(/BOOM/).to_stdout
    expect(command.status).to eq("fail")
  end

  it "reports a command whose if check was killed by a signal as interrupted" do
    command =
      Command.new(
        { "name" => "checked", "if" => "kill -INT $$", "shell" => "true" },
      )

    command.run

    expect(command.status).to eq("interrupted")
  end

  it "skips, rather than crashes on, a command whose if check names a missing tool" do
    command =
      Command.new(
        {
          "name" => "checked",
          "if" => "gpush-no-such-tool",
          "shell" => "true",
        },
      )

    command.run

    expect(command.status).to eq("skipped")
  end

  it "skips a command whose if check exits non-zero" do
    command =
      Command.new({ "name" => "checked", "if" => "exit 1", "shell" => "true" })

    command.run

    expect(command.status).to eq("skipped")
  end

  it "fails parallel_run when a command's thread raises unexpectedly" do
    allow_any_instance_of(Command).to receive(:read_output).and_raise(
      IOError,
      "closed stream",
    )
    result = nil

    expect {
      result =
        Command.run_in_parallel?(
          [{ "name" => "breaks", "shell" => "true" }],
          options: {
            spinner: false,
          },
        )
    }.to output(/breaks: .*FAIL/).to_stdout

    expect(result).to be(false)
  end
end
