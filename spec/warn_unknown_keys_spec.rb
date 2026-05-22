require "spec_helper"
require_relative "../src/ruby/gpush.rb"

RSpec.describe "unknown key warnings" do
  before do
    Dir.chdir(__dir__)
  end

  it "warns on an unknown top-level config key" do
    expect {
      GpushCli.run(%w[--dry-run --config-file=gpush_unknown_toplevel_key.yml])
    }.to output(/WARNING: Unknown config key 'typo_key' in top-level config/).to_stdout
  end

  it "warns on an unknown key inside a command" do
    expect {
      GpushCli.run(%w[--dry-run --config-file=gpush_unknown_command_key.yml])
    }.to output(/WARNING: Unknown config key 'typo_key' in command 'a command'/).to_stdout
  end
end
