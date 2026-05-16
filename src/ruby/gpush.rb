#!/usr/bin/env ruby
require "optparse"
require_relative "gpush_version"
require_relative "command" # Import the external command runner
require_relative "config_helper" # Import the config helper
require_relative "exit_helper" # Import the exit helper
require_relative "git_helper" # Import Git helper methods
require_relative "gpush_error" # Import the custom error handling
require_relative "gpush_diff_branch" # Import the diff-branch subcommand
require_relative "gpush_fix" # Import the fix command
require_relative "gpush_options_parser" # Import the options parser
require_relative "gpush_run" # Import the version checker
require_relative "notifier" # Import the desktop notifier
require_relative "version_checker" # Import the version checker
require_relative "worktree_helper" # Import the worktree helper

EXITING_MESSAGE = "\nExiting gpush.".freeze

SUBCOMMANDS = {
  "run" => {
    klass: GpushRun,
    description:
      "Run one entry from parallel_run in gpushrc by name (matching ignores spaces, dashes, case).",
  },
  "fix" => {
    klass: GpushFix,
    description:
      "Run every shell command in the fix: section of gpushrc, in order.",
  },
  "diff-branch" => {
    klass: GpushDiffBranch,
    description:
      "Print the remote ref (e.g. origin/main) that gpush_changed_files uses for git diff; honors optional gpush_changed_files: settings in gpushrc.",
  },
}.freeze

module Gpush
  class << self
    def parse_cmd(str, verbose:)
      verbose ? str : "#{str} > /dev/null 2>&1"
    end

    def simple_run_commands_with_output(commands, title:, verbose:)
      return if commands.nil? || commands.empty?
      some_verbose = verbose || commands.any? { |cmd| cmd["verbose"] }

      puts "\n"
      print "Running #{title}..."
      puts "\n" if some_verbose

      commands.each do |cmd_dict|
        # Use command's verbose setting if specified, otherwise use global verbose setting
        command_verbose =
          cmd_dict["verbose"].nil? ? verbose : cmd_dict["verbose"]
        command = Command.new(cmd_dict, verbose: command_verbose)
        command.run
        next if command.success?

        message = "#{title} command failed - #{command.name}"
        message += " (`#{command.shell}`)" if command.shell != command.name
        puts "#{message}\nHalting further execution and exiting gpush"
        exit 1 # Halt execution if a command fails
      end

      some_verbose ? puts("#{title} DONE") : print("DONE\n")
      puts "\n"
    end

    def go(options)
      dry_run = options[:dry_run]
      puts "Starting dry run" if dry_run

      will_set_up_remote_branch = false # Initialize the flag

      # Check if a remote branch is set up and up to date
      if GitHelper.not_a_git_repository?
        puts "Not inside a Git repository. Exiting."
        return
      elsif !dry_run && GitHelper.detached_head?
        puts "Cannot push from a detached HEAD"
        if GitHelper.ask_yes_no("Run tests anyway?", default: true)
          puts "Entering dry run mode"
          dry_run = true
        else
          puts EXITING_MESSAGE
          return
        end
      elsif !dry_run && !GitHelper.remote_branch_name
        will_set_up_remote_branch =
          GitHelper.user_wants_to_set_up_remote_branch?
      elsif !dry_run && GitHelper.behind_remote_branch?
        puts "Cannot push to remote branch"
        output = `git status | grep 'branch'`
        output = `git status | grep 'HEAD'` if output.empty?
        output = `git status` if output.empty?
        puts output
        if GitHelper.ask_yes_no("Run tests anyway?", default: true)
          puts "Entering dry run mode"
          dry_run = true
        else
          puts EXITING_MESSAGE
          return
        end
      elsif !dry_run
        unless GitHelper.up_to_date_or_ahead_of_remote_branch?
          puts "Local branch is not up to date with the remote branch. Exiting."
          return
        end

        # Ask user if they want to run tests if up to date
        if GitHelper.at_same_commit_as_remote_branch?
          question =
            "Your branch is up to date with origin (nothing to push). Run tests anyway?"
          if GitHelper.ask_yes_no(question, default: true)
            puts "Entering dry run mode"
            dry_run = true
          else
            puts EXITING_MESSAGE
            return
          end
        end
      end

      if will_set_up_remote_branch && options[:worktree]
        puts "Cannot create a new remote branch from a worktree (git push -u requires a real branch)."
        unless GitHelper.ask_yes_no("Run without worktree?", default: true)
          puts EXITING_MESSAGE
          return
        end
        options[:worktree] = false
      end

      original_dir = Dir.pwd
      original_branch = GitHelper.local_branch_name
      worktree_path = nil

      if options[:worktree]
        git_root = GitHelper.git_root_dir
        ENV["GPUSH_BRANCH"] = original_branch
        worktree_path =
          WorktreeHelper.create(
            git_root: git_root,
            symlink_dirs: options[:worktree_symlink_dirs] || [],
          )
        at_exit { WorktreeHelper.remove(worktree_path) }
        puts "Running in worktree: #{worktree_path}"

        if options[:worktree_copy_gitignored]
          puts "Copying gitignored files into worktree..."
          WorktreeHelper.copy_gitignored(
            git_root: git_root,
            worktree_path: worktree_path,
            globs: options[:worktree_copy_gitignored],
          )
        end

        Dir.chdir(worktree_path)
      end

      verbose = options[:verbose]

      simple_run_commands_with_output(
        options[worktree_path ? :worktree_pre_run : :no_worktree_pre_run],
        title: worktree_path ? "worktree-pre-run" : "no-worktree-pre-run",
        verbose:,
      )

      simple_run_commands_with_output(
        options[:pre_run],
        title: "pre-run",
        verbose:,
      )

      success = Command.run_in_parallel?(options[:parallel_run], verbose:)

      simple_run_commands_with_output(
        options[:post_run],
        title: "post-run",
        verbose:,
      )

      simple_run_commands_with_output(
        options[worktree_path ? :worktree_post_run : :no_worktree_post_run],
        title: worktree_path ? "worktree-post-run" : "no-worktree-post-run",
        verbose:,
      )

      unless success
        simple_run_commands_with_output(
          options[:post_run_failure],
          title: "post-run failure",
          verbose:,
        )
        Notifier.notify(success: false)
        puts "Exiting gpush."
        return
      end

      simple_run_commands_with_output(
        options[:post_run_success],
        title: "post-run success",
        verbose:,
      )

      Notifier.notify(success: true)

      if dry_run
        puts "《 Dry run completed 》"
      else
        push_dir = worktree_path || original_dir
        Dir.chdir(push_dir) do
          if will_set_up_remote_branch
            puts "Setting up the remote branch..."
            Kernel.system("git push -u origin #{original_branch}")
          else
            Kernel.system("git push origin HEAD:#{original_branch}")
          end
        end

        puts "《 #{options[:success_emoji] || "🌺"} 》 Good job! You're doing great."
      end

      # Check for updates after a successful run (even in dry run mode)
      VersionChecker.print_message_if_new_version(VERSION)
    end

    def option_definitions
      lambda do |opts, parsing_options|
        subcmd_width = SUBCOMMANDS.keys.map(&:length).max
        subcommands_block =
          SUBCOMMANDS
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
          "--copy-gitignored[=GLOBS]",
          "Copy gitignored files into the worktree; optionally comma-separated globs (overrides config)",
        ) do |v|
          parsing_options[:worktree_copy_gitignored] = v ? v.split(",") : true
        end
        opts.on(
          "--no-copy-gitignored",
          "Skip copying gitignored files into the worktree (overrides config)",
        ) { parsing_options[:worktree_copy_gitignored] = false }

        opts.on_tail("--version", "Show version") do
          puts "gpush #{VERSION}"
          ExitHelper.exit(0)
        end
      end
    end

    def cl(argv)
      subcommand = SUBCOMMANDS.keys.find { |key| argv[0] == key }
      klass = subcommand ? SUBCOMMANDS.fetch(subcommand).fetch(:klass) : Gpush

      parser_verbose = argv.include?("-v") || argv.include?("--verbose")

      # Dup so OptionParser.parse! can strip flags; remaining entries are positional args for go().
      arg_slice = (subcommand ? argv[1..] : argv).dup

      # Use GpushOptionsParser to parse command-line arguments
      options =
        GpushOptionsParser.parse(
          arg_slice,
          config_prefix: nil,
          option_definitions: klass.option_definitions,
          verbose: parser_verbose,
          is_subcommand: !!subcommand,
        )

      # Execute gpush workflow
      subcommand ? klass.go(args: arg_slice, options:) : Gpush.go(options)
    rescue GpushError, OptionParser::InvalidOption => e
      ExitHelper.exit_with_error(e)
    end
  end
end

Gpush.cl(ARGV) if __FILE__ == $PROGRAM_NAME
