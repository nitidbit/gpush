#!/usr/bin/env ruby
require "yaml"
require "optparse"
require_relative "command" # Import the external command runner
require_relative "gpush_error" # Import the custom error handling
require_relative "git_helper" # Import Git helper methods

VERSION = "2.0.3"
EXITING_MESSAGE = "\nExiting gpush."

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
  return YAML.load_file File.join(File.dirname(__FILE__), "gpushrc_default.yml")
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

def simple_run_command(cmd, title:, verbose:)
  raise GpushError, 'Command must have a "shell" field.' unless cmd["shell"]
  passed_if = cmd["if"] ? system(parse_cmd(cmd["if"], verbose: verbose)) : true
  return unless passed_if

  command_success = system(parse_cmd(cmd["shell"], verbose: verbose))
  unless command_success
    raise GpushError, "#{title} command failed: #{cmd["shell"]}"
  end

  true
end

def simple_run_commands_with_output(commands, title:, verbose:)
  return if commands.empty?

  print "Running #{title}..."
  puts "\n\n" if verbose
  commands.each do |cmd_dict|
    simple_run_command(cmd_dict, title: title, verbose: verbose)
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
  simple_run_commands_with_output(
    pre_run_commands,
    title: "pre-run",
    verbose: verbose,
  )

  # Run parallel run commands
  success = Command.run_in_parallel(parallel_run_commands, verbose: verbose)

  simple_run_commands_with_output(
    post_run_commands,
    title: "post-run",
    verbose: verbose,
  )

  if !success
    simple_run_commands_with_output(
      post_run_failure_commands,
      title: "post-run failure",
      verbose: verbose,
    )
    puts "Exiting gpush."
    return
  end

  simple_run_commands_with_output(
    post_run_success_commands,
    title: "post-run success",
    verbose: verbose,
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
rescue GpushError => error
  puts "\n\n"
  puts "Gpush encountered an error:"
  puts error.message
  puts EXITING_MESSAGE
end

$options = {}
OptionParser
  .new do |opts|
    opts.banner = "Usage: gpush [options]"

    opts.on("--dry-run", "Simulate the commands without executing") do
      $options[:dry_run] = true
    end

    opts.on("-v", "--verbose", "prints command output while running") do
      $options[:verbose] = true
    end

    opts.on_tail("--version", "Show version") do
      puts "gpush #{VERSION}"
      exit
    end
  end
  .parse!

# Execute gpush workflow
go(dry_run: $options[:dry_run], verbose: $options[:verbose])
