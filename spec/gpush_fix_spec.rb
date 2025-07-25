require "rspec"
require_relative "../src/ruby/gpush_error.rb"
require_relative "../src/ruby/gpush.rb"

RSpec.describe "gpush fix" do
  before do
    Dir.chdir(__dir__)

    allow(ExitHelper).to receive(:exit) do |code|
      raise "Exit called with code #{code}"
    end
  end

  context "when running gpush fix" do
    it "should report an error if the config file is empty" do
      expect(YAML).to receive(:load_file).and_return({})
      expect { Gpush.cl(["fix"]) }.to raise_error(
        GpushError,
        "Configuration file is empty!",
      )
    end

    it "should report an error if the fix section is not found in the config file" do
      expect(YAML).to receive(:load_file).and_return({ gpush_version: ">=1.0" })
      expect { Gpush.cl(["fix"]) }.to raise_error(
        "Exit called with code 1",
      ).and output(
              /#{Regexp.escape("No fix section found in config file")}/,
            ).to_stdout
    end

    it "should report an error if the fix section is empty" do
      expect(YAML).to receive(:load_file).and_return({ "fix" => [] })
      expect { Gpush.cl(["fix"]) }.to raise_error(
        "Exit called with code 1",
      ).and output(/#{Regexp.escape("Fix section is empty")}/).to_stdout
    end

    it "should run commands defined under the fix section in config sequentially and exit with success when all commands succeed" do
      expect(YAML).to receive(:load_file).and_return(
        {
          "fix" => [
            { "shell" => "echo 'hello'", "name" => "howdy" },
            { "shell" => "echo 'world'" },
          ],
        },
      )
      expect { Gpush.cl(["fix"]) }.to raise_error(
        "Exit called with code 0",
      ).and output(/howdy.*hello.*echo 'world'.*world/m).to_stdout
    end

    it "should exit with error when any fix command fails" do
      expect(YAML).to receive(:load_file).and_return(
        { fix: [{ "shell" => "exit 1" }] },
      )
      expect { Gpush.cl(["fix"]) }.to raise_error("Exit called with code 1")
    end
  end
end
