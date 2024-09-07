#!/usr/bin/env ruby
require 'yaml'
require 'optparse'
require_relative 'command' # Import the external command runner
require_relative 'gpush_error' # Import the custom error handling
require_relative 'git_helper'

def parse_config
  config_paths = ['./gpushrc.yml', './gpushrc.yaml', File.join(File.dirname(__FILE__), 'gpushrc_default.yml')]

  config_paths.each do |path|
    if File.exist?(path)
      puts "Using config file: #{path}"
      return YAML.load_file(path)
    end
  end

  raise GpushError, 'No configuration file found!'
end

def go(dry_run: false)
  if !GitHelper.remote_branch_name
    will_set_up_remote_branch = GitHelper.check_remote_branch
  elsif !GitHelper.up_to_date_with_remote_branch?
    raise GpushError, 'Local branch is not up to date with the remote branch. Exiting.'
  end

  config = parse_config

  pre_run_commands = config['pre_run'] || []
  parallel_run_commands = config['parallel_run'] || []
  post_run_commands = config['post_run'] || []

  # Run pre-run commands
  pre_run_commands.each do |cmd_dict|
    command = Command.new(cmd_dict)  # Pass the working directory
    command.run unless dry_run
  end

  # Run parallel run commands
  errors = Command.run_in_parallel(parallel_run_commands)  # Pass the working directory

  if errors > 0
    puts "《 Errors detected 》 Exiting gpush."
    return
  end

  if dry_run
    puts "《 Dry run completed 》 No errors detected."
  else
    # Perform git push if not dry-run
    system("git push")
    post_run_commands.each do |cmd_dict|
      command = Command.new(cmd_dict)  # Pass the working directory
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
