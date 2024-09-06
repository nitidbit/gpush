#!/usr/bin/env ruby
require 'open3'
require 'yaml'
require 'optparse'
require 'pty'

class GpushError < StandardError; end

class Command
  attr_reader :name, :shell, :status

  def initialize(command_dict)
    @shell = command_dict['shell'] || raise(GpushError, 'Command must have a "shell" field.')
    @name = command_dict['name'] || @shell
    @status = 'not started'
    @output = ""
  end

  def run
    puts "\nRunning: #{@name}"
    @status = 'working'

    begin
      # Spawn a new PTY process to capture real-time output
      PTY.spawn(@shell) do |stdout, stdin, pid|
        begin
          # Read the output as it comes and store it
          stdout.each do |line|
            @output << line
            print line # Print the output to the terminal immediately to retain color
          end
        rescue Errno::EIO
          # EIO happens when the process ends, it's expected, so do nothing here
        end

        _, status = Process.wait2(pid)
        if status.success?
          @status = 'success'
        else
          @status = 'fail'
          raise GpushError, "Command #{@name} failed with exit code #{status.exitstatus}."
        end
      end
    rescue PTY::ChildExited
      puts "The child process exited!"
    end

    # After the process completes, post the stored output
    post_output
  end

  private

  def post_output
    puts "Output for #{@name}:"
    puts @output
  end
end

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

$options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: gpush [options]"

  opts.on('--dry-run', 'Simulate the commands without executing') do
    $options[:dry_run] = true
  end
end.parse!

def run_all(commands, in_parallel: false)
  if in_parallel
    threads = commands.map do |cmd_dict|
      Thread.new do
        command = Command.new(cmd_dict)
        if $options[:dry_run]
          puts "Dry run: Would run command #{command.name} in parallel"
        else
          command.run
        end
      end
    end
    threads.each(&:join)
  else
    commands.each do |cmd_dict|
      command = Command.new(cmd_dict)
      if $options[:dry_run]
        puts "Dry run: Would run command #{command.name}"
      else
        command.run
      end
    end
  end
end

def main
  config = parse_config
  pre_run_commands = config['pre_run'] || []
  parallel_run_commands = config['parallel_run'] || []

  begin
    puts "Running pre-run commands..."
    run_all(pre_run_commands)

    puts "Running parallel commands..."
    run_all(parallel_run_commands, in_parallel: true)

    puts "All commands completed successfully."
  rescue GpushError => e
    puts "Error: #{e.message}"
    exit 1
  end
end

if __FILE__ == $0
  main
end
