#!/usr/bin/env ruby
require "optparse"
require_relative "command" # Import the external command runner
require_relative "config_helper" # Import the config helper
require_relative "exit_helper" # Import the exit helper
require_relative "git_helper" # Import Git helper methods
require_relative "gpush_error" # Import the custom error handling
require_relative "gpush_fix" # Import the fix command
require_relative "gpush_options_parser" # Import the options parser
require_relative "gpush_run" # Import the version checker
require_relative "notifier" # Import the desktop notifier
require_relative "version_checker" # Import the version checker

EXITING_MESSAGE = "\nExiting gpush.".freeze

DEFAULT_VERSION = "local-development".freeze # Default for uninstalled scripts
VERSION = ENV["GPUSH_VERSION"] || DEFAULT_VERSION
SUBCOMMANDS = { "run" => GpushRun, "fix" => GpushFix }.freeze

module Gpush
  class << self
    def parse_cmd(str, verbose:)
      verbose ? str : "#{str} > /dev/null 2>&1"
    end

    def simple_run_commands_with_output(commands, title:, verbose:)
      return if commands.empty?
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

      pre_run_commands = options[:pre_run] || []
      parallel_run_commands = options[:parallel_run] || []
      post_run_commands = options[:post_run] || []
      post_run_success_commands = options[:post_run_success] || []
      post_run_failure_commands = options[:post_run_failure] || []
      verbose = options[:verbose]

      # Run pre-run commands
      simple_run_commands_with_output(
        pre_run_commands,
        title: "pre-run",
        verbose:,
      )

      # Run parallel run commands
      success = Command.run_in_parallel?(parallel_run_commands, verbose:)

      simple_run_commands_with_output(
        post_run_commands,
        title: "post-run",
        verbose:,
      )

      unless success
        simple_run_commands_with_output(
          post_run_failure_commands,
          title: "post-run failure",
          verbose:,
        )
        Notifier.notify(success: false)
        puts "Exiting gpush."
        return
      end

      simple_run_commands_with_output(
        post_run_success_commands,
        title: "post-run success",
        verbose:,
      )

      Notifier.notify(success: true)

      if dry_run
        puts "《 Dry run completed 》"
      else
        # Perform git push based on whether we are setting up a remote branch or just pushing
        if will_set_up_remote_branch
          puts "Setting up the remote branch..." unless dry_run
          Kernel.system("git push -u origin HEAD") unless dry_run
        else
          Kernel.system("git push") unless dry_run
        end

        puts "《 #{options[:success_emoji] || "🌺"} 》 Good job! You're doing great."
      end

      # Check for updates after a successful run (even in dry run mode)
      VersionChecker.print_message_if_new_version(VERSION)
    end

    def cl(argv)
      subcommand = argv[0]

      if subcommand && !SUBCOMMANDS.key?(subcommand)
        puts "Unexpected argument(s): #{argv.join(" ")}"
        puts "Run 'gpush --help' for usage information."
        exit 1
      end

      # Use GpushOptionsParser to parse command-line arguments
      options =
        GpushOptionsParser.parse(
          argv,
          config_prefix: subcommand,
          option_definitions:
            lambda do |opts, parsing_options|
              opts.banner =
                "Usage:\ngpush [options] OR gpush [subcommand] [options]\n\nSubcommands:\n#{SUBCOMMANDS.keys.join("\n")}\n\nOptions:"

              opts.on("--dry-run", "Simulate the commands without executing") do
                parsing_options[:dry_run] = true
              end

              opts.on(
                "-v",
                "--verbose",
                "Prints command output while running",
              ) { parsing_options[:verbose] = true }

              opts.on(
                "--config-file=FILE",
                "Specify a custom config file",
              ) { |file| parsing_options[:config_file] = file }

              opts.on_tail("--version", "Show version") do
                puts "gpush #{VERSION}"
                ExitHelper.exit(0)
              end
            end,
          required_options: [], # No required options
        )

      # Execute gpush workflow
      if subcommand
        SUBCOMMANDS[subcommand].go(args: argv[1..], options:)
      else
        Gpush.go(options)
      end
    rescue GpushError => e
      ExitHelper.exit_with_error(e)
    end
  end
end

Gpush.cl(ARGV) if __FILE__ == $PROGRAM_NAME
