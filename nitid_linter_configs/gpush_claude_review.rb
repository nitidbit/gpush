require "json"

ALLOWED_TOOLS = [
  "Bash(gpush diff-branch)",
  "Bash(git diff*)",
  "Bash(git log*)",
  "Bash(git show*)",
].freeze

PROMPT = <<~PROMPT.freeze
  Run `gpush diff-branch` first. It should return exactly one git branch name (the
  base branch).

  Then review changes from that base to HEAD using:
  - `git diff <base>...HEAD`
  - `git log <base>..HEAD`
  - `git show <sha>` when needed for context

  Use the git commit messages to inform your review.

  Review for:
  - Bugs and regressions
  - Typos
  - Security vulnerabilities
  - Violations of repo conventions
  - Anything that should block commit

  Do not report low-value style nits.

  Format your output for a terminal — plain text, no markdown. Use blank lines for
  separation and dashes for bullet points.

  - For each finding include:
    - Severity: HIGH | MEDIUM | LOW
    - Location: `path/to/file:line` (or range)
    - Issue: what is wrong
    - Fix: exact recommended change

  If no blocking issues, print a brief summary of changes.

  The final line must be the word EXIT followed by a number; exactly one of:
  - `EXIT 0` (no changes needed)
  - `EXIT 1` (issues found)
  - `EXIT 2` (could not complete due to tooling/access)

PROMPT

output = ""
cmd = [
  "claude",
  "--print",
  "--output-format",
  "stream-json",
  "--verbose",
  "--include-partial-messages",
  "--allowedTools",
  ALLOWED_TOOLS.join(","),
]

IO.popen(cmd, "r+") do |io|
  io.write(PROMPT)
  io.close_write
  io.each_line do |line|
    event =
      begin
        JSON.parse(line)
      rescue StandardError
        next
      end
    next unless event["type"] == "stream_event"
    delta = event.dig("event", "delta")
    next unless delta&.dig("type") == "text_delta"
    text = delta["text"]
    print text
    output << text
  end
end

puts # ensure newline after streaming

last_line = output.strip.lines.last&.strip

case last_line
when "EXIT 0"
  exit 0
when "EXIT 1"
  exit 1
when "EXIT 2"
  exit 2
else
  warn "ERROR: Claude did not produce a valid exit code. Last line was: #{last_line.inspect}"
  exit 3
end
