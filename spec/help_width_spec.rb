require "spec_helper"
require "stringio"
require_relative "../src/ruby/gpush.rb"

# Help text is wrapped to HelpText::WIDTH columns so it stays readable in a
# narrow terminal, a split pane, or a pasted issue. HelpText.wrap does the
# wrapping, but nothing forces a banner heredoc or a bare opts.on description
# to go through it, so this spec is what keeps the limit true.
RSpec.describe "help output width" do
  # Runs a command's --help and returns what it printed. ExitHelper.exit is
  # stubbed in spec_helper to raise, which is how -h unwinds.
  def help_output(argv)
    captured = StringIO.new
    original_stdout = $stdout
    $stdout = captured
    begin
      GpushCli.run(argv + ["--help"])
    rescue RuntimeError => e
      raise unless e.message == "Exit called with code 0"
    ensure
      $stdout = original_stdout
    end
    captured.string
  end

  def overlong_lines(text)
    text
      .lines
      .map
      .with_index(1) { |line, number| [number, line.chomp] }
      .select { |_number, line| line.length > HelpText::WIDTH }
  end

  def failure_report(label, lines)
    report =
      lines
        .map { |number, line| "  line #{number} (#{line.length}): #{line}" }
        .join("\n")
    "#{label} --help has #{lines.length} line(s) over " \
      "#{HelpText::WIDTH} columns:\n#{report}"
  end

  [[], *GpushCli::SUBCOMMANDS.keys.map { |name| [name] }].each do |argv|
    label = ["gpush", *argv].join(" ")

    it "wraps #{label} --help to #{HelpText::WIDTH} columns" do
      lines = overlong_lines(help_output(argv))
      expect(lines).to be_empty, failure_report(label, lines)
    end
  end
end
