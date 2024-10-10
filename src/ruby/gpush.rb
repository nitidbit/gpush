#!/usr/bin/env ruby
require "yaml"
require "optparse"
require_relative "command" # Import the external command runner
require_relative "gpush_error" # Import the custom error handling
require_relative "git_helper" # Import Git helper methods

VERSION = "2.2.3".freeze

def parse_config
  config_paths = %w[./gpushrc.yml ./gpushrc.yaml]
  config_file = config_paths.find { |path| File.exist?(path) }

  if config_file
    puts "Using config file: #{config_file}"
    config = YAML.load_file(config_file)
    return config unless config.empty?
    raise GpushError, "Configuration file is empty!"
  end

  puts "No configuration file found. Looking for #{config_paths.join(", ")}"
  puts "Using default configuration."
  YAML.load_file File.join(File.dirname(__FILE__), "gpushrc_default.yml")
end

def check_up_to_date_with_origin
  if GitHelper.up_to_date_with_remote_branch?
    puts "Your branch is up to date with origin. Run tests anyway? (Y/n)"
    response = gets.chomp.downcase
    return response.empty? || response[0].downcase == "y"
  end
  true
end

def parse_cmd(str, verbose:)
  verbose ? str : "#{str} > /dev/null 2>&1"
end

def simple_run_commands_with_output(commands, title:, verbose:)
  return if commands.empty?

  print "Running #{title}..."
  puts "\n\n" if verbose

  commands.each do |cmd_dict|
    command = Command.new(cmd_dict, verbose:)
    command.run
    next if command.success?

    message = "#{title} command failed - #{command.name}"
    message += " (`#{command.shell}`)" if command.shell != command.name
    puts "#{message}\nHalting further execution and exiting gpush"
    exit 1 # Halt execution if a command fails
  end

  puts "\n\n" if verbose
  print "#{verbose ? title : ""} DONE"
  puts "\n\n"
end

def go(dry_run: false, verbose: false)
  puts "Starting dry run" if dry_run

  will_set_up_remote_branch = false # Initialize the flag

  # Check if a remote branch is set up and up to date
  if GitHelper.not_a_git_repository?
    puts "Not inside a Git repository. Exiting."
    return
  elsif GitHelper.detached_head?
    puts "Cannot push from a detached HEAD"
    if GitHelper.ask_yes_no("Run tests anyway?", default: true)
      puts "Entering dry run mode"
      dry_run = true
    else
      puts EXITING_MESSAGE
      return
    end
  elsif !dry_run && !GitHelper.remote_branch_name
    will_set_up_remote_branch = GitHelper.user_wants_to_set_up_remote_branch?
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

  config = parse_config

  pre_run_commands = config["pre_run"] || []
  parallel_run_commands = config["parallel_run"] || []
  post_run_commands = config["post_run"] || []
  post_run_success_commands = config["post_run_success"] || []
  post_run_failure_commands = config["post_run_failure"] || []

  # Run pre-run commands
  simple_run_commands_with_output(pre_run_commands, title: "pre-run", verbose:)

  # Run parallel run commands
  success = Command.run_in_parallel(parallel_run_commands, verbose:)

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
    puts "Exiting gpush."
    return
  end

  simple_run_commands_with_output(
    post_run_success_commands,
    title: "post-run success",
    verbose:,
  )

  if dry_run
    puts "《 Dry run completed 》"
  else
    # Perform git push based on whether we are setting up a remote branch or just pushing
    if will_set_up_remote_branch
      puts "Setting up the remote branch..." unless dry_run
      system("git push -u origin HEAD") unless dry_run
    else
      system("git push") unless dry_run
    end

    puts "《 #{config["success_emoji"] || "🌺"} 》 Good job! You're doing great."
  end
rescue GpushError => e
  GitHelper.exit_with_error(e)
end

def run_one_command_and_exit(command_input)
  cmd_dict =
    parse_config["parallel_run"].find do |cmd|
      (cmd["name"] || cmd["shell"]).strip.gsub(/\s/, "").downcase ==
        command_input.gsub(/\s/, "").downcase
    end
  if cmd_dict
    command = Command.new(cmd_dict, verbose: true, prefix_output: false)
    message = "Running command: #{command.name}"
    puts "#{Command::COLORS[:bold]}========== #{message} ==========#{Command::COLORS[:reset]}"
    command.run
    puts ""
    puts command.final_summary
    exit command.success? ? 0 : 1
  else
    puts "Command not found: #{command_input}"
    puts "gpush run looks for a command in the parallel_run section of the config file."
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

    opts.on("-v", "--verbose", "prints command output while running") do
      options[:verbose] = true
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
  exit
end

# Check for unexpected arguments after options parsing
unless ARGV.empty?
  if ARGV[0] == "run"
    if options.any?
      puts "Unexpected option(s): #{options.keys.join(", ")}"
      puts "gpush run does not accept any options."
      puts "Run 'gpush --help' for usage information."
      exit 1
    end
    if ARGV.length == 1
      puts "Enter a command to run (e.g., gpush run test_name)"
      exit 1
    else
      run_one_command_and_exit(ARGV[1..].join(" "))
    end
  else
    puts "Unexpected argument(s): #{ARGV.join(" ")}"
    puts "Run 'gpush --help' for usage information."
    exit 1
  end
end

# Execute gpush workflow
go(dry_run: options[:dry_run], verbose: options[:verbose])
