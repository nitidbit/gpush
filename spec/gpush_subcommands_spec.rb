require "spec_helper"
require_relative "../src/ruby/gpush.rb"

RSpec.describe "gpush changed-files" do
  before { Dir.chdir(__dir__) }

  def mock_changed_files(diff_output)
    expect(GitHelper).to receive(:local_branch_name).and_return("mybranch")
    expect(GitHelper).to receive(:branch_exists_on_origin?).with(
      "mybranch",
    ).and_return(true)
    allow(GitHelper).to receive(:git_root_dir).and_return(__dir__)
    allow(Open3).to receive(:capture2).with(
      "git diff --name-only origin/mybranch",
    ).and_return([diff_output, double(success?: true)])
  end

  it "prints the changed files and exits 0" do
    expect(YAML).to receive(:load_file).and_return(
      { "gpush_version" => ">=1.0" },
    )
    mock_changed_files("spec_helper.rb\nmock_system.rb\n")

    expect { GpushCli.run(%w[changed-files]) }.to output(
      "spec_helper.rb mock_system.rb\n",
    ).to_stdout.and raise_error("Exit called with code 0")
  end

  it "exits 1 when no files changed" do
    expect(YAML).to receive(:load_file).and_return(
      { "gpush_version" => ">=1.0" },
    )
    mock_changed_files("")

    expect { GpushCli.run(%w[changed-files]) }.to raise_error(
      "Exit called with code 1",
    )
  end

  it "accepts a --pattern option" do
    expect(YAML).to receive(:load_file).and_return(
      { "gpush_version" => ">=1.0" },
    )
    mock_changed_files("spec_helper.rb\nmock_system.rb\n")

    expect { GpushCli.run(%w[changed-files --pattern spec_*.rb]) }.to output(
      "spec_helper.rb\n",
    ).to_stdout.and raise_error("Exit called with code 0")
  end

  it "honors the gpush_changed_files section of the config" do
    expect(YAML).to receive(:load_file).and_return(
      {
        "gpush_version" => ">=1.0",
        "gpush_changed_files" => {
          "separator" => ",",
        },
      },
    )
    mock_changed_files("spec_helper.rb\nmock_system.rb\n")

    expect { GpushCli.run(%w[changed-files]) }.to output(
      "spec_helper.rb,mock_system.rb\n",
    ).to_stdout.and raise_error("Exit called with code 0")
  end

  it "rejects extra arguments" do
    expect(YAML).to receive(:load_file).and_return(
      { "gpush_version" => ">=1.0" },
    )

    expect { GpushCli.run(%w[changed-files extra]) }.to output(
      /Unexpected argument/,
    ).to_stdout.and raise_error("Exit called with code 1")
  end
end

RSpec.describe "gpush get-specs" do
  before { Dir.chdir(__dir__) }

  it "prints spec files matching keywords from the changed files and exits 0" do
    expect(YAML).to receive(:load_file).and_return(
      {
        "gpush_version" => ">=1.0",
        "get_specs" => {
          "include_pattern" => "*_spec.rb",
          "exclude_words" => %w[gpush],
        },
      },
    )
    expect(GitHelper).to receive(:local_branch_name).and_return("mybranch")
    expect(GitHelper).to receive(:branch_exists_on_origin?).with(
      "mybranch",
    ).and_return(true)
    allow(GitHelper).to receive(:git_root_dir).and_return(__dir__)
    allow(Open3).to receive(:capture2).with(
      "git diff --name-only origin/mybranch",
    ).and_return(["version_checker.rb\n", double(success?: true)])

    expect { GpushCli.run(%w[get-specs]) }.to output(
      "#{__dir__}/version_checker_spec.rb\n",
    ).to_stdout.and raise_error("Exit called with code 0")
  end

  it "rejects extra arguments" do
    expect(YAML).to receive(:load_file).and_return(
      { "gpush_version" => ">=1.0" },
    )

    expect { GpushCli.run(%w[get-specs extra]) }.to output(
      /Unexpected argument/,
    ).to_stdout.and raise_error("Exit called with code 1")
  end
end
