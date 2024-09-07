#!/usr/bin/env ruby
require 'yaml'
require 'optparse'
require_relative 'command'     # Import the external command runner
require_relative 'gpush_error' # Import the custom error handling
require_relative 'git_helper'  # Import Git helper methods

def parse_config
  config_paths = ['./gpushrc.yml', './gpushrc.yaml', File.join(File.dirname(__FILE__), 'gpushrc_default.yml')]

  config_paths.each do |path|
    if File.exist?(path)
      puts "Using config file: #{path}"
      config = YAML.load_file(path)
      return config unless config.nil? || config.empty?
    end
  end

  raise GpushError, 'No configuration file found or configuration is empty!'
end

def go(dry_run: false)
  will_set_up_remote_branch = false  # Initialize the flag

  # Check if a remote branch is set up and up to date
  if !dry_run && !GitHelper.remote_branch_name
    will_set_up_remote_branch = GitHelper.check_remote_branch
  elsif !dry_run && !GitHelper.up_to_date_with_remote_branch?
    puts 'Local branch is not up to date with the remote branch. Exiting.'
    return
  end

  config = parse_config

  pre_run_commands = config['pre_run'] || []
  parallel_run_commands = config['parallel_run'] || []
  post_run_commands = config['post_run'] || []

  # Run pre-run commands
  pre_run_commands.each do |cmd_dict|
    command = Command.new(cmd_dict)  # Assuming Command class takes a hash or dict
    command.run unless dry_run
  end

  # Run parallel run commands
  errors = Command.run_in_parallel(parallel_run_commands)  # Assuming this method handles error checking

  if errors > 0
    puts "《 Errors detected 》 Exiting gpush."
    return
  end

  if dry_run
    puts "《 Dry run completed 》 No errors detected."
  else
    # Perform git push based on whether we are setting up a remote branch or just pushing
    if will_set_up_remote_branch
      puts "Setting up the remote branch..." unless dry_run
      system("git push -u origin HEAD") unless dry_run
    else
      system("git push") unless dry_run
    end

    # Run post-run commands
    post_run_commands.each do |cmd_dict|
      command = Command.new(cmd_dict)
      command.run
    end
    puts "《 🌺 》 Good job! You're doing great."
  end
end

$options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: gpush [options]"

  opts.on('--dry-run', 'Simulate the commands without executing') do
    $options[:dry_run] = true
  end
end.parse!

# Execute gpush workflow
go(dry_run: $options[:dry_run])
