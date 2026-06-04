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

# Stream agent output as it arrives, in order, ahead of any script output below.
$stdout.sync = true

# String.new produces mutable strings
output = String.new
result_event = nil

IO.popen(cmd + [{ err: %i[child out] }], "r+") do |io|
  io.write(prompt)
  io.close_write
  io.each_line do |line|
    event =
      begin
        JSON.parse(line)
      rescue StandardError
        # Non-JSON line (e.g. a CLI error) — show it in order rather than hide it.
        print line
        output << line
        next
      end
    case event["type"]
    when "stream_event"
      delta = event.dig("event", "delta")
      next unless delta&.dig("type") == "text_delta"
      text = delta["text"]
      print text
      output << text
    when "result"
      result_event = event
    end
  end
end

st = Process.last_status

# If nothing streamed (no text_delta events), fall back to the final result text
# so the agent output is always printed before the script output below.
if output.strip.empty? && result_event && result_event["result"].is_a?(String)
  print result_event["result"]
  output << result_event["result"]
end

exit(st.exitstatus || 1) unless st.success?

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
