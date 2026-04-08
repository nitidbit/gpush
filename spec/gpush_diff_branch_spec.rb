require "spec_helper"
require_relative "../src/ruby/gpush.rb"

RSpec.describe "gpush diff-branch" do
  before { Dir.chdir(__dir__) }

  it "prints origin/<branch> and exits 0" do
    expect(YAML).to receive(:load_file).and_return({ "gpush_version" => ">=1.0" })
    expect(GitHelper).to receive(:local_branch_name).and_return("mybranch")
    expect(GitHelper).to receive(:branch_exists_on_origin?).with("mybranch").and_return(
      true,
    )

    expect { Gpush.cl(%w[diff-branch]) }.to output("origin/mybranch\n").to_stdout.and raise_error(
      "Exit called with code 0",
    )
  end

  it "rejects extra arguments" do
    expect(YAML).to receive(:load_file).and_return({ "gpush_version" => ">=1.0" })

    expect { Gpush.cl(%w[diff-branch extra]) }.to output(
      /Unexpected argument/,
    ).to_stdout.and raise_error("Exit called with code 1")
  end
end
