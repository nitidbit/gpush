# frozen_string_literal: true

require_relative "gpush_options_parser"
require_relative "gpush_error"
require_relative "exit_helper"

module GpushCli
  SUBCOMMANDS = {
    "run" => {
      klass: -> { GpushRun },
      description:
        "Run one entry from parallel_run in gpushrc by name (matching ignores spaces, dashes, case).",
    },
    "fix" => {
      klass: -> { GpushFix },
      description:
        "Run every shell command in the fix: section of gpushrc, in order.",
    },
    "diff-branch" => {
      klass: -> { GpushDiffBranch },
      description:
        "Print the remote ref (e.g. origin/main) that gpush_changed_files uses for git diff; honors optional gpush_changed_files: settings in gpushrc.",
    },
  }.freeze

  def self.run(argv)
    run_with(argv, subcommands: SUBCOMMANDS, main_klass: Gpush)
  end

  def self.option_definitions(subcommands)
    lambda do |opts, parsing_options|
      subcmd_width = subcommands.keys.map(&:length).max
      subcommands_block =
        subcommands
          .map do |name, meta|
            format("  %-#{subcmd_width}s  %s", name, meta[:description])
          end
          .join("\n")

      opts.banner = <<~BANNER
        gpush: run pre-push checks from gpushrc, then push (unless --dry-run).

        Usage:
          gpush [options]                      Full workflow: pre_run, parallel_run, post_run, then git push
          gpush SUBCOMMAND [options] [args]    Subcommand (see below)

        Subcommands:
        #{subcommands_block}

        Other programs installed with this package:
          gpush_changed_files   List paths changed vs the same origin ref as above (see diff-branch).
          gpush_get_specs       List spec files to run for those changes.

        More help:
          gpush SUBCOMMAND --help    Options for run, fix, or diff-branch

        Options:
      BANNER

      opts.on("--dry-run", "Simulate the commands without executing") do
        parsing_options[:dry_run] = true
      end

      opts.on("-v", "--verbose", "Prints command output while running") do
        parsing_options[:verbose] = true
      end

      opts.on("--config-file=FILE", "Specify a custom config file") do |file|
        parsing_options[:config_file] = file
      end

      opts.on(
        "--[no-]worktree",
        "Run checks in an isolated git worktree (overrides config)",
      ) { |v| parsing_options[:worktree] = v }

      opts.on(
        "--worktree-copy-gitignored[=GLOBS]",
        "Copy gitignored files into the worktree; optionally comma-separated globs (overrides config)",
      ) do |v|
        parsing_options[:worktree_copy_gitignored] = v ? v.split(",") : true
      end

      opts.on(
        "--no-worktree-copy-gitignored",
        "Skip copying gitignored files into the worktree (overrides config)",
      ) { parsing_options[:worktree_copy_gitignored] = false }

      opts.on_tail("--version", "Show version") do
        puts "gpush #{VERSION}"
        ExitHelper.exit(0)
      end
    end
  end

  def self.run_with(argv, subcommands:, main_klass:)
    subcommand = subcommands.keys.find { |key| argv[0] == key }
    klass =
      subcommand ? subcommands.fetch(subcommand).fetch(:klass).call : main_klass

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
