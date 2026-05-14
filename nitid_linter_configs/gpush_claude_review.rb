# frozen_string_literal: true

require "json"

INSTRUCTIONS_FILE = File.join(__dir__, "gpush_claude_review_instructions.md")

ALLOWED_TOOLS = [
  "Bash(gpush diff-branch)",
  "Bash(git diff*)",
  "Bash(git log*)",
  "Bash(git show*)",
].freeze

prompt =
  begin
    File.read(INSTRUCTIONS_FILE)
  rescue Errno::ENOENT
    warn "ERROR: Instructions file not found: #{INSTRUCTIONS_FILE}"
    exit 9
  end

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

# String.new produces mutable strings
output = String.new
raw_stdout = String.new

IO.popen(cmd + [{ err: %i[child out] }], "r+") do |io|
  io.write(prompt)
  io.close_write
  io.each_line do |line|
    event =
      begin
        JSON.parse(line)
      rescue StandardError
        raw_stdout << line
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

st = Process.last_status
unless st.success?
  warn raw_stdout unless raw_stdout.empty?
  exit(st.exitstatus || 1)
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
