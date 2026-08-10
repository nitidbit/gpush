# frozen_string_literal: true

require_relative "gpush_claude_agent"
require_relative "exit_helper"
require_relative "help_text"

module GpushClaudeReview
  # Effort levels passed through on the slash-command line. Lower levels give
  # fewer, higher-confidence findings; a pre-push gate defaults to medium to
  # avoid blocking on nits. /code-review documents these; /security-review may
  # not, but we send them the same way and let Claude interpret.
  EFFORT_LEVELS = %w[low medium high xhigh max].freeze
  DEFAULT_EFFORT = "medium"

  DO_NOT_LINT = <<~MD.strip.freeze
    Do not report lint, formatter, or style-cop findings (RuboCop, Prettier,
    stylelint, ERB Lint, eslint, etc). Assume those tests are running
    in parallel and will report their findings definitively. Your guess
    about whether a cop fires is noise at best and wrong at worst.
  MD

  USE_THE_DIFF = <<~MD.strip.freeze
    Use the git range on the slash-command line (base...HEAD) as the
    diff to review. Prefer it over any default base the skill suggests.
  MD

  MODE_CONFIG = {
    "code" => {
      skill: "code-review",
      guidance_file: "REVIEW.md",
      extra_sections: [USE_THE_DIFF, DO_NOT_LINT],
    }.freeze,
    "security" => {
      skill: "security-review",
      guidance_file: "SECURITY.md",
      extra_sections: [USE_THE_DIFF],
    }.freeze,
  }.freeze

  MODES = MODE_CONFIG.keys.freeze
  DEFAULT_MODE = "code"

  class << self
    def description
      "Review the branch diff with the Claude CLI; blocking findings exit nonzero."
    end

    def go(args:, options:)
      mode = options[:mode] || DEFAULT_MODE
      unless MODE_CONFIG.key?(mode)
        puts "Invalid --mode #{mode.inspect}. " \
               "Choose one of: #{MODES.join(", ")}."
        ExitHelper.exit(1)
      end

      effort = options[:effort] || DEFAULT_EFFORT
      unless EFFORT_LEVELS.include?(effort)
        puts "Invalid --effort #{effort.inspect}. " \
               "Choose one of: #{EFFORT_LEVELS.join(", ")}."
        ExitHelper.exit(1)
      end

      GpushClaudeAgent.prepare_and_run!(
        args:,
        options:,
        usage: "gpush claude-review [options]",
      ) do |base_ref|
        build_prompt(
          base_ref,
          mode:,
          effort:,
          instructions: options[:instructions] || [],
        )
      end
    end

    def option_definitions
      lambda do |opts, parsing_options|
        opts.banner = <<~BANNER
          #{HelpText.hanging("gpush claude-review: #{description}")}

          Usage:
            gpush claude-review [options]

          Runs a Claude review skill over the diff-branch base to HEAD via the
          claude CLI, streaming the review to the terminal. Exit status: 0 no
          blocking issues, 1 blocking issues found, 2 review could not complete
          (reported by Claude), 3 no usable EXIT line (CLI failure, quota, or
          malformed output).

          --mode=code (default) runs /code-review and follows REVIEW.md when
          present. --mode=security runs /security-review and follows SECURITY.md
          when present.

          The review loads no Claude settings files and inherits none of your
          local permissions. It can read the repo and run read-only git
          commands, nothing else. A project that needs more can grant it with
          --allowed-tools in gpushrc.yml, where the grant is committed and so
          applies identically for everyone.

          Use --effort to tune review depth. The --instructions/--instructions-file
          options append extra guidance to the prompt, in the order given, and are
          repeatable.

          Options:
        BANNER
        opts.on(
          "--mode=MODE",
          *HelpText.option(
            "Review mode: #{MODES.join(" | ")} (default #{DEFAULT_MODE})",
          ),
        ) { |v| parsing_options[:mode] = v }
        opts.on(
          "--effort=LEVEL",
          *HelpText.option(
            "Review effort: #{EFFORT_LEVELS.join(" | ")} " \
              "(default #{DEFAULT_EFFORT})",
          ),
        ) { |v| parsing_options[:effort] = v }
        GpushClaudeAgent.add_common_options(opts, parsing_options)
      end
    end

    def build_prompt(base_ref, mode:, effort: DEFAULT_EFFORT, instructions: [])
      config =
        MODE_CONFIG.fetch(mode) do
          raise ArgumentError, "unknown mode: #{mode.inspect}"
        end

      GpushClaudeAgent.build_prompt(
        lead: "/#{config[:skill]} #{effort} #{base_ref}...HEAD",
        guidance_file: config[:guidance_file],
        instructions:,
        extra_sections: config[:extra_sections],
      )
    end
  end
end
