# frozen_string_literal: true

require "json"
require_relative "exit_helper"
require_relative "gpush_changed_files"
require_relative "gpush_claude_cli"
require_relative "gpush_error"
require_relative "help_text"

# Shared Claude CLI runner for gpush claude-review (and any future Claude
# review subcommands). Owns the EXIT-line contract, stream-json plumbing, and
# the --instructions / --allowed-tools option helpers. Callers supply the
# slash-command lead line, guidance file name, and any skill-specific sections.
module GpushClaudeAgent
  # Read-only git commands reviews need to inspect the diff. gpush passes the
  # base ref in the prompt, so no base discovery is needed. Read is permitted
  # by default, and the CLI sandbox already runs read-only shell commands
  # (grep, find, git status/blame/ls-files) without an allow rule, so this
  # list only needs the git commands that carry the diff.
  DEFAULT_ALLOWED_TOOLS = [
    "Bash(git diff*)",
    "Bash(git log*)",
    "Bash(git show*)",
  ].freeze

  # claude_command passes --setting-sources, which older CLIs do not know. They
  # would fail with an opaque "unknown option" error part-way through a gpush
  # run, so check up front instead. 2.1.1 is the oldest release confirmed to
  # support the flag; lower this if an older one is verified.
  MINIMUM_CLAUDE_VERSION = "2.1.1"

  # Trailing prompt block every review shares: terminal formatting + the EXIT
  # line gpush parses for its exit status.
  EXIT_INSTRUCTIONS = <<~MD.strip.freeze
    Write the review as plain text for a terminal: no JSON, and do not wrap
    the review, code snippets, or file paths in Markdown code fences.

    The very last line of your response must be the word EXIT, a single
    space, then a single digit (0, 1, or 2):

    - EXIT 0 = approved
    - EXIT 1 = rejected
    - EXIT 2 = review could not complete (tooling/access)

    Nothing should follow the EXIT line.
  MD

  class << self
    # lead: slash-command line, e.g. "/code-review medium origin/main...HEAD"
    # guidance_file: e.g. "REVIEW.md" — mentioned so Claude reads it if present
    # extra_sections: skill-specific paragraphs (lint exclusion, etc.)
    # instructions: [{ file: }, { text: }, ...] from --instructions*
    def build_prompt(
      lead:,
      guidance_file:,
      instructions: [],
      extra_sections: []
    )
      parts = [lead, <<~MD.strip, *extra_sections, EXIT_INSTRUCTIONS]
          If #{guidance_file} exists at the repository root, read it and follow its
          guidance for this review.
        MD

      additions =
        instructions.map do |part|
          part[:file] ? read_or_raise(part[:file]) : part[:text]
        end
      [*parts, *additions].join("\n\n")
    end

    def exit_code_from(output)
      # Claude sometimes appends a trailing code fence and/or blank lines after
      # the EXIT line, despite being told not to. Step back past those so a
      # stray ``` doesn't get mistaken for a malformed exit.
      empty_line_or_code_fence = /\A`*\z/
      lines = output.lines
      i = lines.length - 1
      i -= 1 while i >= 0 && lines[i].strip.match?(empty_line_or_code_fence)
      # Guard i explicitly: lines[-1] would wrap to the last element, not nil.
      last_line = i >= 0 ? lines[i].strip : nil
      return Regexp.last_match(1).to_i if last_line =~ /\AEXIT ([012])\z/

      warn "ERROR: Claude did not produce a valid exit code. " \
             "Last line was: #{last_line.inspect}"
      3
    end

    # Shared --instructions / --instructions-file / --allowed-tools flags.
    def add_common_options(opts, parsing_options)
      opts.on(
        "--instructions-file=FILE",
        *HelpText.option("Append instructions from FILE (repeatable)"),
      ) { |v| (parsing_options[:instructions] ||= []) << { file: v } }
      opts.on(
        "--instructions=TEXT",
        *HelpText.option("Append instruction TEXT (repeatable)"),
      ) { |v| (parsing_options[:instructions] ||= []) << { text: v } }
      opts.on(
        "--allowed-tools=TOOLS",
        *HelpText.option(
          "Permit TOOLS in addition to the read-only default, in claude " \
            "--allowedTools syntax, comma-separated (repeatable)",
        ),
      ) { |v| (parsing_options[:allowed_tools] ||= []) << v }
    end

    # Resolve the diff base, exit early when empty, then run Claude with the
    # prompt returned by the block (|base_ref|).
    def prepare_and_run!(
      args:,
      options:,
      usage:,
      allowed_tools: DEFAULT_ALLOWED_TOOLS
    )
      if args.any?
        puts "Unexpected argument(s): #{args.join(", ")}"
        puts "Usage: #{usage}"
        ExitHelper.exit(1)
      end

      changed_files = GpushChangedFiles.from_options(options)
      base_ref = changed_files.diff_base_ref

      if changed_files.all_changed_files.empty?
        puts "Nothing to review (no changes vs #{base_ref})."
        ExitHelper.exit(0)
      end

      GpushClaudeCli.check_version!(MINIMUM_CLAUDE_VERSION)
      GpushClaudeCli.check_auth!
      run(
        prompt: yield(base_ref),
        allowed_tools:,
        extra_tools: options[:allowed_tools] || [],
      )
    end

    # extra_tools comes from --allowed-tools, i.e. from gpushrc.yml or the
    # command line — both committed or explicit, never the developer's local
    # settings, so the review stays reproducible across machines.
    def claude_command(allowed_tools:, extra_tools: [])
      [
        "claude",
        "--print",
        "--output-format",
        "stream-json",
        "--verbose",
        "--include-partial-messages",
        # Load no settings files (user, project or local), so the review starts
        # from zero permissions and behaves identically on every machine.
        # --allowedTools is additive: without this the review also inherits
        # whatever the developer has already allowed — e.g. a stray
        # "Bash(bundle exec rspec *)" in .claude/settings.local.json lets the
        # reviewer run the test suite alongside gpush's own Rspec step.
        "--setting-sources",
        "",
        "--allowedTools",
        (allowed_tools + extra_tools).join(","),
      ]
    end

    def run(prompt:, allowed_tools:, extra_tools: [])
      # Stream agent output as it arrives, in order, ahead of any output below.
      $stdout.sync = true

      output = String.new
      result_event = nil

      command =
        claude_command(allowed_tools:, extra_tools:) + [{ err: %i[child out] }]
      IO.popen(command, "r+") do |io|
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

      # Claude never got to print an EXIT line (quota, crash, signal, …).
      # Same bucket as a missing/malformed EXIT: gpush could not read a result.
      ExitHelper.exit(3) unless status.success?

      puts # ensure newline after streaming
      ExitHelper.exit(exit_code_from(output))
    end

    private

    def read_or_raise(path)
      File.read(path)
    rescue Errno::ENOENT
      raise GpushError, "Instructions file not found: #{path}"
    end
  end
end
