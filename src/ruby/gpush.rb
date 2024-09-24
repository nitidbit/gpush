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

def check_up_to_date_with_origin
  if GitHelper.up_to_date_with_remote_branch?
    puts 'Your branch is up to date with origin. Run tests anyway? (yes/no)'
    response = gets.chomp.downcase
    return response == 'yes'
  end
  true
end

def parse_cmd(str, verbose:)
  verbose ? str : "#{str} > /dev/null 2>&1"
end

def simple_run_command(cmd, verbose:)
  raise GpushError, 'Command must have a "shell" field.' unless cmd['shell']

  return unless cmd['if'].nil? || system(parse_cmd(command['if'], verbose:))
  system parse_cmd cmd['shell'], verbose:
end

def simple_run_commands_with_output(commands, title:, verbose:)
  return if commands.empty?

  print "Running #{title}..."
  puts "\n\n" if verbose
  commands.each { |cmd_dict| simple_run_command(cmd_dict, verbose:) }
  puts "\n\n" if verbose
  print "#{verbose ? title : ''} DONE"
  puts "\n\n"
end

def go(dry_run: false, verbose: false)
  will_set_up_remote_branch = false  # Initialize the flag

  # Check if a remote branch is set up and up to date
  if !dry_run && !GitHelper.remote_branch_name
    will_set_up_remote_branch = GitHelper.check_remote_branch
  elsif !dry_run
    unless GitHelper.up_to_date_or_ahead_of_remote_branch?
      puts 'Local branch is not up to date with the remote branch. Exiting.'
      return
    end

    # Ask user if they want to run tests if up to date
    if GitHelper.at_same_commit_as_remote_branch?
      print 'Your branch is up to date with origin (nothing to push). Run tests anyway? (y/n) '
      response = gets.chomp.downcase
      if response != 'y'
        puts 'Quitting.'
        return
      else
        dry_run = true
      end
    end
  end

  config = parse_config

  pre_run_commands = config['pre_run'] || []
  parallel_run_commands = config['parallel_run'] || []
  post_run_commands = config['post_run'] || []

  # Run pre-run commands
  simple_run_commands_with_output(pre_run_commands, title: 'pre-run commands', verbose: verbose)

  # Run parallel run commands
  errors = Command.run_in_parallel(parallel_run_commands, verbose: verbose)

  if errors > 0
    puts "《 Errors detected 》 Exiting gpush."
    return
  end

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

    # Run post-run commands
    simple_run_commands_with_output(post_run_commands, title: 'post-run commands', verbose: verbose)

    puts "《 🌺 》 Good job! You're doing great."
  end
end

$options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: gpush [options]"

  opts.on('--dry-run', 'Simulate the commands without executing') do
    $options[:dry_run] = true
  end

  opts.on('-v', '--verbose', 'prints command output while running') do
    $options[:verbose] = true
  end
end.parse!

# Execute gpush workflow
go(dry_run: $options[:dry_run], verbose: $options[:verbose])
