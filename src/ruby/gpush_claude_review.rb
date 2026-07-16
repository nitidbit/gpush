# frozen_string_literal: true

require "json"
require "open3"
require_relative "exit_helper"
require_relative "gpush_changed_files"
require_relative "gpush_error"

module GpushClaudeReview
  # Basic review instructions ship with the package, next to this script.
  BASE_INSTRUCTIONS_PATH =
    File.join(__dir__, "gpush_claude_review_instructions.md")

  ALLOWED_TOOLS = [
    "Bash(git diff*)",
    "Bash(git log*)",
    "Bash(git show*)",
  ].freeze

  class << self
    def description
      "Review the branch diff with the Claude CLI; blocking findings exit nonzero."
    end

    def go(args:, options:)
      if args.any?
        puts "Unexpected argument(s): #{args.join(", ")}"
        puts "Usage: gpush claude-review [options]"
        ExitHelper.exit(1)
      end

      # Resolve the base ref here (rather than having claude run gpush
      # diff-branch) and exit early when there is nothing to review.
      changed_files = GpushChangedFiles.from_options(options)
      base_ref = changed_files.diff_base_ref

      if changed_files.all_changed_files.empty?
        puts "Nothing to review (no changes vs #{base_ref})."
        ExitHelper.exit(0)
      end

      check_claude_auth!
      prompt = [
        "Review the git changes from #{base_ref} to HEAD. " \
          "Use #{base_ref} as the base ref for all diff commands.",
        build_prompt(options[:instructions] || []),
      ].join("\n\n")
      run_review(prompt)
    end

    def option_definitions
      lambda do |opts, parsing_options|
        opts.banner = <<~BANNER
          gpush claude-review: #{description}

          Usage:
            gpush claude-review [options]

          Reviews changes from the diff-branch base to HEAD using the claude CLI,
          streaming the review to the terminal. Exit status: 0 no blocking issues,
          1 blocking issues found, 2 review could not complete, 3 malformed exit line.

          Built-in review instructions are included automatically. Both options below
          append to them in the order given, and both are repeatable.

          Options:
        BANNER
        opts.on(
          "--instructions-file=FILE",
          "Append instructions from FILE (repeatable)",
        ) { |v| (parsing_options[:instructions] ||= []) << { file: v } }
        opts.on(
          "--instructions=TEXT",
          "Append instruction TEXT (repeatable)",
        ) { |v| (parsing_options[:instructions] ||= []) << { text: v } }
      end
    end

    def build_prompt(instructions)
      base = read_or_raise(BASE_INSTRUCTIONS_PATH)
      additions =
        instructions.map do |part|
          part[:file] ? read_or_raise(part[:file]) : part[:text]
        end
      [base, *additions].join("\n\n")
    end

    def exit_code_from(output)
      last_line = output.strip.lines.last&.strip
      return Regexp.last_match(1).to_i if last_line =~ /\AEXIT ([012])\z/

      warn "ERROR: Claude did not produce a valid exit code. " \
             "Last line was: #{last_line.inspect}"
      3
    end

    private

    def read_or_raise(path)
      File.read(path)
    rescue Errno::ENOENT
      raise GpushError, "Instructions file not found: #{path}"
    end

    def check_claude_auth!
      stdout, stderr, process_status =
        begin
          Open3.capture3("claude", "auth", "status")
        rescue Errno::ENOENT
          raise GpushError,
                "`claude` CLI not found on PATH. Install it or skip this check."
        end

      unless process_status.success?
        detail = stderr.strip.empty? ? stdout.strip : stderr.strip
        raise GpushError,
              "`claude auth status` failed (exit #{process_status.exitstatus}). " \
                "Is the `claude` CLI installed and on PATH?" \
                "#{"\n#{detail}" unless detail.empty?}"
      end

      status =
        begin
          JSON.parse(stdout)
        rescue JSON::ParserError
          raise GpushError,
                "Unexpected output from `claude auth status` (expected JSON):\n#{stdout.strip}"
        end
      return if status["loggedIn"]

      raise GpushError,
            "Not logged in to Claude. Run `claude auth login` to authenticate."
    end

    def claude_command
      [
        "claude",
        "--print",
        "--output-format",
        "stream-json",
        "--verbose",
        "--include-partial-messages",
        "--allowedTools",
        ALLOWED_TOOLS.join(","),
      ]
    end

    def run_review(prompt)
      # Stream agent output as it arrives, in order, ahead of any output below.
      $stdout.sync = true

      output = String.new
      result_event = nil

      IO.popen(claude_command + [{ err: %i[child out] }], "r+") do |io|
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
            print delta["text"]
            output << delta["text"]
          when "result"
            result_event = event
          end
        end
      end

      status = Process.last_status

      # If nothing streamed (no text_delta events), fall back to the final result
      # text so the agent output is always printed.
      if output.strip.empty? && result_event &&
           result_event["result"].is_a?(String)
        print result_event["result"]
        output << result_event["result"]
      end

      ExitHelper.exit(status.exitstatus || 1) unless status.success?

      puts # ensure newline after streaming
      ExitHelper.exit(exit_code_from(output))
    end
  end
end
