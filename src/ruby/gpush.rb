#!/usr/bin/env ruby
require "optparse"
require_relative "command" # Import the external command runner
require_relative "config_helper" # Import the config helper
require_relative "gpush_error" # Import the custom error handling
require_relative "git_helper" # Import Git helper methods
require_relative "gpush_options_parser" # Import the options parser
require_relative "notifier" # Import the desktop notifier
require_relative "version_checker" # Import the version checker

EXITING_MESSAGE = "\nExiting gpush.".freeze

DEFAULT_VERSION = "local-development".freeze # Default for uninstalled scripts
VERSION = ENV["GPUSH_VERSION"] || DEFAULT_VERSION

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

    def go(dry_run: false, verbose: false, config_file: nil)
      puts "Using config file: #{ConfigHelper.display_config_file_path(config_file)}"
      config = ConfigHelper.parse_config(config_file)

      GpushOptionsParser.check_version(VERSION, config)

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

      pre_run_commands = config["pre_run"] || []
      parallel_run_commands = config["parallel_run"] || []
      post_run_commands = config["post_run"] || []
      post_run_success_commands = config["post_run_success"] || []
      post_run_failure_commands = config["post_run_failure"] || []

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

        puts "《 #{config["success_emoji"] || "🌺"} 》 Good job! You're doing great."
      end

      # Check for updates after a successful run (even in dry run mode)
      VersionChecker.print_message_if_new_version(VERSION)
    rescue GpushError => e
      GitHelper.exit_with_error(e)
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  # Check for unexpected arguments after options parsing
  unless ARGV.empty?
    if ARGV[0] == "run"
      GpushRun.go(args: ARGV[1..], options:)
    else
      puts "Unexpected argument(s): #{ARGV.join(" ")}"
      puts "Run 'gpush --help' for usage information."
      exit 1
    end
  end

  options = {}
  options_parser =
    OptionParser.new do |opts|
      opts.banner = "Usage: gpush [options] OR gpush run COMMAND\nOPTIONS:"

      opts.on("--dry-run", "Simulate the commands without executing") do
        options[:dry_run] = true
      end

      opts.on("-v", "--verbose", "Prints command output while running") do
        options[:verbose] = true
      end

      opts.on("--config_file=FILE", "Specify a custom config file") do |file|
        options[:config_file] = file
      end

      opts.on_tail("--version", "Show version") do
        puts "gpush #{VERSION}"
        exit
      end

      opts.on_tail("-h", "--help", "Show this message") do
        puts opts
        exit
      end
    end
  begin
    options_parser.parse!
  rescue OptionParser::InvalidOption => e
    puts e
    puts "Run 'gpush --help' for usage information."
    exit 1
  end

  # Execute gpush workflow
  Gpush.go(
    dry_run: options[:dry_run],
    verbose: options[:verbose],
    config_file: options[:config_file],
  )
end
