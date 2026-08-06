# frozen_string_literal: true

require "json"
require "open3"
require_relative "exit_helper"
require_relative "gpush_changed_files"
require_relative "gpush_error"

module GpushClaudeReview
  # Read-only git commands the /code-review skill needs to inspect the diff.
  # gpush passes the base ref in the prompt, so no base discovery is needed.
  # Read is permitted by default, and the CLI sandbox already runs read-only
  # shell commands (grep, find, git status/blame/ls-files) without an allow
  # rule, so this list only needs the git commands that carry the diff.
  ALLOWED_TOOLS = [
    "Bash(git diff*)",
    "Bash(git log*)",
    "Bash(git show*)",
  ].freeze

  # claude_command passes --setting-sources, which older CLIs do not know. They
  # would fail with an opaque "unknown option" error part-way through a gpush
  # run, so check up front instead. 2.1.1 is the oldest release confirmed to
  # support the flag; lower this if an older one is verified.
  MINIMUM_CLAUDE_VERSION = "2.1.1"

  # /code-review effort levels. Lower levels give fewer, higher-confidence
  # findings; a pre-push gate defaults to medium to avoid blocking on nits.
  EFFORT_LEVELS = %w[low medium high xhigh max].freeze
  DEFAULT_EFFORT = "medium"

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

      effort = options[:effort] || DEFAULT_EFFORT
      unless EFFORT_LEVELS.include?(effort)
        puts "Invalid --effort #{effort.inspect}. " \
               "Choose one of: #{EFFORT_LEVELS.join(", ")}."
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

      check_claude_version!
      check_claude_auth!
      run_review(
        build_prompt(base_ref, effort, options[:instructions] || []),
        options[:allowed_tools] || [],
      )
    end

    def option_definitions
      lambda do |opts, parsing_options|
        opts.banner = <<~BANNER
          gpush claude-review: #{description}

          Usage:
            gpush claude-review [options]

          Runs the /code-review skill over the diff-branch base to HEAD via the
          claude CLI, streaming the review to the terminal. Exit status: 0 no
          blocking issues, 1 blocking issues found, 2 review could not complete,
          3 malformed exit line.

          The review loads no Claude settings files and inherits none of your
          local permissions. It can read the repo and run read-only git
          commands, nothing else. A project that needs more can grant it with
          --allowed-tools in gpushrc.yml, where the grant is committed and so
          applies identically for everyone.

          A REVIEW.md at the repository root, if present, is read and followed
          for per-repo review guidance.

          Use --effort to tune review depth. The --instructions/--instructions-file
          options append extra guidance to the prompt, in the order given, and are
          repeatable.

          Options:
        BANNER
        opts.on(
          "--effort=LEVEL",
          "Review effort: #{EFFORT_LEVELS.join(" | ")} (default #{DEFAULT_EFFORT})",
        ) { |v| parsing_options[:effort] = v }
        opts.on(
          "--instructions-file=FILE",
          "Append instructions from FILE (repeatable)",
        ) { |v| (parsing_options[:instructions] ||= []) << { file: v } }
        opts.on(
          "--instructions=TEXT",
          "Append instruction TEXT (repeatable)",
        ) { |v| (parsing_options[:instructions] ||= []) << { text: v } }
        opts.on(
          "--allowed-tools=TOOLS",
          "Permit TOOLS in addition to the read-only default, in claude " \
            "--allowedTools syntax, comma-separated (repeatable)",
        ) { |v| (parsing_options[:allowed_tools] ||= []) << v }
      end
    end

    # The complete prompt sent to the claude CLI: hand the diff to the
    # /code-review skill, then pin the trailing EXIT line gpush reads for its
    # exit status. Any --instructions/--instructions-file text is appended.
    def build_prompt(base_ref, effort, instructions)
      base = <<~MD.strip
        /code-review #{effort} #{base_ref}...HEAD

        If REVIEW.md exists at the repository root, read it and follow its
        guidance for this review.

        Write the review as plain text for a terminal: no JSON, and do not wrap
        the review, code snippets, or file paths in Markdown code fences.

        The very last line of your response must be the word EXIT, a single
        space, then a single digit (0, 1, or 2):

        - EXIT 0 = approved
        - EXIT 1 = rejected
        - EXIT 2 = review could not complete (tooling/access)

        Nothing should follow the EXIT line.
      MD
      additions =
        instructions.map do |part|
          part[:file] ? read_or_raise(part[:file]) : part[:text]
        end
      [base, *additions].join("\n\n")
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

    private

    def read_or_raise(path)
      File.read(path)
    rescue Errno::ENOENT
      raise GpushError, "Instructions file not found: #{path}"
    end

    def check_claude_version!
      stdout, stderr, process_status =
        begin
          Open3.capture3("claude", "--version")
        rescue Errno::ENOENT
          raise GpushError,
                "`claude` CLI not found on PATH. Install it or skip this check."
        end

      unless process_status.success?
        detail = stderr.strip.empty? ? stdout.strip : stderr.strip
        raise GpushError,
              "`claude --version` failed (exit #{process_status.exitstatus})." \
                "#{"\n#{detail}" unless detail.empty?}"
      end

      # e.g. "2.1.223 (Claude Code)"
      found = stdout[/\d+(?:\.\d+)+/]
      unless found
        raise GpushError,
              "Could not read a version from `claude --version`: " \
                "#{stdout.strip.inspect}"
      end

      minimum = Gem::Version.new(MINIMUM_CLAUDE_VERSION)
      return if Gem::Version.new(found) >= minimum

      raise GpushError,
            "claude CLI #{found} is too old for gpush claude-review, which " \
              "needs #{MINIMUM_CLAUDE_VERSION} or newer. Update the CLI and try again."
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

    # extra_tools comes from --allowed-tools, i.e. from gpushrc.yml or the
    # command line -- both committed or explicit, never the developer's local
    # settings, so the review stays reproducible across machines.
    def claude_command(extra_tools = [])
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
        # whatever the developer has already allowed -- e.g. a stray
        # "Bash(bundle exec rspec *)" in .claude/settings.local.json lets the
        # reviewer run the test suite alongside gpush's own Rspec step.
        "--setting-sources",
        "",
        "--allowedTools",
        (ALLOWED_TOOLS + extra_tools).join(","),
      ]
    end

    def run_review(prompt, extra_tools = [])
      # Stream agent output as it arrives, in order, ahead of any output below.
      $stdout.sync = true

      output = String.new
      result_event = nil

      command = claude_command(extra_tools) + [{ err: %i[child out] }]
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

      ExitHelper.exit(status.exitstatus || 1) unless status.success?

      puts # ensure newline after streaming
      ExitHelper.exit(exit_code_from(output))
    end
  end
end
