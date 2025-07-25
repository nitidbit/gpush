require "rspec"
require_relative "../src/ruby/gpush_error.rb"
require_relative "../src/ruby/gpush.rb"

RSpec.describe "gpush fix" do
  before { Dir.chdir(__dir__) }

  context "when running gpush fix" do
    it "should report an error if the config file is empty" do
      expect(YAML).to receive(:load_file).and_return({})
      expect { Gpush.cl(["fix"]) }.to output(
        /Configuration file is empty/,
      ).to_stdout.and raise_error("Exit called with code 1")
    end

    it "should report an error if the fix section is not found in the config file" do
      expect(YAML).to receive(:load_file).and_return({ gpush_version: ">=1.0" })
      expect { Gpush.cl(["fix"]) }.to output(
        /#{Regexp.escape("No fix section found in config file")}/,
      ).to_stdout.and raise_error("Exit called with code 1")
    end

    it "should report an error if the fix section is empty" do
      expect(YAML).to receive(:load_file).and_return({ "fix" => [] })
      expect { Gpush.cl(["fix"]) }.to output(
        /#{Regexp.escape("Fix section is empty")}/,
      ).to_stdout.and raise_error("Exit called with code 1")
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
      expect { Gpush.cl(["fix"]) }.to output(
        /howdy.*hello.*echo 'world'.*world/m,
      ).to_stdout.and raise_error("Exit called with code 0")
    end

    it "should exit with error when any fix command fails" do
      expect(YAML).to receive(:load_file).and_return(
        { fix: [{ "shell" => "exit 1" }] },
      )
      expect { Gpush.cl(["fix"]) }.to output(
        /#{Regexp.escape("running shell command `exit 1`")}/xm,
      ).to_stdout.and raise_error("Exit called with code 1")
    end
  end
end
