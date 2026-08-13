# frozen_string_literal: true

require_relative "gpush_options_parser"
require_relative "gpush_error"
require_relative "exit_helper"
require_relative "help_text"

module GpushCli
  # name => lazy class reference; each class provides .description and .go
  SUBCOMMANDS = {
    "run" => -> { GpushRun },
    "fix" => -> { GpushFix },
    "diff-branch" => -> { GpushDiffBranch },
    "changed-files" => -> { GpushChangedFiles },
    "get-specs" => -> { GpushGetSpecs },
    "claude-review" => -> { GpushClaudeReview },
  }.freeze

  def self.run(argv)
    run_with(argv, subcommands: SUBCOMMANDS, main_klass: Gpush)
  end

  def self.option_definitions(subcommands)
    lambda do |opts, parsing_options|
      subcmd_width = subcommands.keys.map(&:length).max
      # Two leading spaces, the name column, then two more before the text.
      subcmd_indent = subcmd_width + 4
      subcommands_block =
        subcommands
          .map do |name, klass_ref|
            description =
              HelpText.hanging(
                klass_ref.call.description,
                indent: subcmd_indent,
              )
            format("  %-#{subcmd_width}s  %s", name, description)
          end
          .join("\n")

      opts.banner = <<~BANNER
        gpush: run your project's checks, then git push if they all pass
        (--dry-run runs the checks but never pushes).

        Usage:
          gpush [options]                      Run the checks, then push
          gpush SUBCOMMAND [options] [args]    Run a subcommand (see below)

        The checks come from the config file gpushrc.yml (or gpushrc.yaml),
        found by walking up from the current directory, or specified with
        --config-file. gpush runs pre_run, then parallel_run, then post_run,
        and pushes only if everything passed.

        Subcommands:
        #{subcommands_block}

        Examples:
          gpush                     Run the checks, then push
          gpush --dry-run           Run the checks, never push
          gpush -v                  Same, streaming each command's output
          gpush run rspec           Run only the parallel_run entry "rspec" (no push)
          gpush fix                 Run the autofixers in the fix: section (no push)

        Deprecated aliases (will be removed in a future version):
          gpush_changed_files   Use 'gpush changed-files' instead.
          gpush_get_specs       Use 'gpush get-specs' instead.

        More help:
          gpush SUBCOMMAND --help    Options for each subcommand
          https://github.com/nitidbit/gpush

        Exit status: 0 if every check passed (pushed or not), 1 if anything failed.

        Options:
      BANNER

      opts.on(
        "--dry-run",
        *HelpText.option(
          "Run every check, then stop without pushing. The checks run for " \
            "real; only the push is skipped, along with the git fetch and " \
            "branch-state checks that precede it.",
        ),
      ) { parsing_options[:dry_run] = true }

      opts.on(
        "-v",
        "--verbose",
        *HelpText.option(
          "Stream each command's output while it runs, instead of printing " \
            "it only on failure",
        ),
      ) { parsing_options[:verbose] = true }

      opts.on(
        "-u",
        "--set-upstream",
        *HelpText.option(
          "Create the branch on origin without asking, when it has no " \
            "remote branch yet. Answers the only prompt that a real push " \
            "can hit, so gpush can run without a terminal.",
        ),
      ) { parsing_options[:set_upstream] = true }

      opts.on(
        "--config-file=FILE",
        *HelpText.option(
          "Use FILE instead of searching for gpushrc.yml/gpushrc.yaml",
        ),
      ) { |file| parsing_options[:config_file] = file }

      opts.on(
        "--[no-]spinner",
        *HelpText.option(
          "Show the live single-line spinner while commands run " \
            "(overrides config)",
        ),
      ) { |v| parsing_options[:spinner] = v }

      opts.on(
        "--[no-]worktree",
        *HelpText.option(
          "Run checks in an isolated git worktree (overrides config)",
        ),
      ) { |v| parsing_options[:worktree] = v }

      opts.on(
        "--worktree-copy-gitignored[=GLOBS]",
        *HelpText.option(
          "Copy gitignored files into the worktree, so checks can see " \
            "things like .env; optionally comma-separated globs to limit " \
            "what is copied (overrides config)",
        ),
      ) do |v|
        parsing_options[:worktree_copy_gitignored] = if v && !v.empty?
          v.split(",")
        else
          true
        end
      end

      opts.on(
        "--no-worktree-copy-gitignored",
        *HelpText.option(
          "Skip copying gitignored files into the worktree (overrides config)",
        ),
      ) { parsing_options[:worktree_copy_gitignored] = false }

      opts.separator ""
      opts.separator "Other options:"

      opts.on_tail("--version", "Show version") do
        puts "gpush #{VERSION}"
        ExitHelper.exit(0)
      end
    end
  end

  def self.run_with(argv, subcommands:, main_klass:)
    subcommand = subcommands.keys.find { |key| argv[0] == key }
    klass = subcommand ? subcommands.fetch(subcommand).call : main_klass

    parser_verbose = argv.include?("-v") || argv.include?("--verbose")
    arg_slice = (subcommand ? argv[1..] : argv).dup

    option_definitions =
      subcommand ? klass.option_definitions : option_definitions(subcommands)

    options =
      GpushOptionsParser.parse(
        arg_slice,
        config_prefix: nil,
        option_definitions: option_definitions,
        verbose: parser_verbose,
        is_subcommand: !!subcommand,
      )

    subcommand ? klass.go(args: arg_slice, options:) : main_klass.go(options)
  rescue GpushError, OptionParser::InvalidOption => e
    ExitHelper.exit_with_error(e)
  end
end
