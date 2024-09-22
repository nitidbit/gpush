#!/usr/bin/env ruby
require 'pty'
require 'io/console'
require_relative 'gpush_error' # Import the custom error handling

class Command
  attr_reader :name, :shell, :status

  COLORS = {
    green: "\e[32m",
    red: "\e[31m",
    white: "\e[37m",
    bold: "\e[1m",
    reset: "\e[0m"
  }.freeze

  SPINNER = ['|', '/', '-', '\\'].freeze

  def initialize(command_dict, index = 0, spinner_status = 'working')
    @shell = command_dict['shell'] || raise(GpushError, 'Command must have a "shell" field.')
    @name = command_dict['name'] || @shell
    @index = index
    @spinner_status = spinner_status
    @status = 'not started'
    @output = []
  end

  def run
    exit_status = nil
    @status = 'working'
    spinner_thread = start_spinner

    begin
      # Use PTY for real-time command output, capturing both stdout and stderr
      PTY.spawn(@shell) do |stdout, _stdin, pid|
        begin
          stdout.each do |line|
            @output << line  # Collect command output into @output
          end
        rescue Errno::EIO
          # End of input
        end

        # Wait for the child process to exit and capture its status
        _, exit_status = Process.wait2(pid)
      end

      if exit_status&.success?
        @status = 'success'
      else
        @status = 'fail'
      end
    rescue PTY::ChildExited
      @status = 'fail'
    ensure
      @spinner_running = false
      spinner_thread.join  # Ensure spinner stops before ending
    end

    # Update spinner status to pass/fail status
    @spinner_status[@index] = @status

    [@output.join, @status]  # Return output and status for later use
  end

  def run_without_spinner
    exit_status = nil
    @status = 'working'

    begin
      # Use PTY for real-time command output, capturing both stdout and stderr
      PTY.spawn(@shell) do |stdout, _stdin, pid|
        begin
          stdout.each do |line|
            @output << line  # Collect command output into @output
          end
        rescue Errno::EIO
          # End of input
        end

        # Wait for the child process to exit and capture its status
        _, exit_status = Process.wait2(pid)
      end

      @status = exit_status&.success? ? 'success' : 'fail'
    rescue PTY::ChildExited
      @status = 'fail'
    end

    [@output.join, @status]  # Return output and status for later use
  end

  private

  def start_spinner
    @spinner_running = true
    Thread.new do
      i = 0
      while @spinner_running
        @spinner_status[@index] = 'working'
        self.class.print_single_line_spinner(i, Command.all_commands, @spinner_status)
        i = (i + 1) % SPINNER.size
        sleep 0.3
      end
      self.class.print_single_line_spinner(i, Command.all_commands, @spinner_status)  # Ensure final status is printed after spinner stops
    end
  end

  # Class method to run commands in parallel and show summary
  def self.run_in_parallel(commands)
    @all_commands = commands
    errors = 0  # Start error counter
    spinner_status = Array.new(commands.size, 'working')  # Initialize spinner status for each command

    threads = commands.map.with_index do |cmd_dict, index|
      Thread.new do
        command = Command.new(cmd_dict, index, spinner_status)
        begin
          output, status = command.run  # Capture the output and status
          cmd_dict[:status] = status == 'success' ? 'success' : 'fail'
          cmd_dict[:output] = output  # Store output for later use

          # If command failed, increment the error counter
          errors += 1 if status == 'fail'
        rescue GpushError
          cmd_dict[:status] = 'fail'
          errors += 1  # Increment errors if an exception occurs
        end
      end
    end

    # Spinner summary box with a single line spinner
    spinner_thread = Thread.new do
      i = 0
      while threads.any?(&:alive?)
        print_single_line_spinner(i, commands, spinner_status)
        i = (i + 1) % SPINNER.size
        sleep 0.3  # Limit the summary box refresh rate
      end
    end

    # Wait for all threads to complete
    threads.each(&:join)
    spinner_thread.kill  # Stop the spinner thread
    # Final spinner print with completed statuses
    print_single_line_spinner(0, commands, spinner_status, show_spinner: false)  # Show all tests in their final state

    # Final output after all threads are done
    puts ""
    commands.each do |cmd|
      next if cmd[:status] == 'success'
      puts "#{COLORS[:bold]}========== Output for: #{cmd['name'] || cmd['shell']} ==========#{COLORS[:reset]}"
      puts cmd[:output]  # Print the buffered output for failed commands
      puts "-" * 30
      puts "\n"
    end

    # Print overall summary
    puts "\n#{COLORS[:bold]}Summary#{COLORS[:reset]}"
    commands.each do |cmd|
      status_color = cmd[:status] == 'success' ? COLORS[:green] : COLORS[:red]  # Green for success, red for fail
      puts "#{cmd['name'] || cmd['shell']}: #{status_color}#{cmd[:status].upcase}#{COLORS[:reset]}"
    end

    # Report any errors encountered
    if errors > 0
      puts "\n#{COLORS[:red]}《 Errors detected 》#{COLORS[:reset]}"
    else
      puts "\n#{COLORS[:green]}《 No errors detected 》#{COLORS[:reset]}"
    end

    errors  # Return the error count
  end

  def self.terminal_width
    width = IO.console.winsize[1] rescue nil
    width ||= `tput cols`.to_i rescue 80
    width > 0 ? width : 80  # Default to 80 if no valid width is found
  end

  def self.truncate_command_name(command, max_length)
    return command if command.length <= max_length
    "#{command[0...max_length - 3]}..."  # Truncate and add ellipsis
  end

  def self.print_single_line_spinner(spinner_index, commands, spinner_status, show_spinner: true)
    # Get terminal width
    max_width = terminal_width

    # Start with the spinner character (no color)
    line = show_spinner ? "[#{SPINNER[spinner_index]}] " : "[⚑] "

    spinner_width = 4  # Width of the spinner and surrounding brackets
    available_width = max_width - spinner_width - commands.size  # Leave space for separators and padding

    command_names = commands.map { |cmd| cmd['name'] || cmd['shell'] }
    over_width = command_names.map(&:size).sum - available_width
    if over_width > 0
      command_names.map! { |name| truncate_command_name(name, available_width / commands.size ) }
    elsif over_width < 0 - command_names.size * 2
      command_names.map! { |name| " #{name} " }
    end

    commands.each_with_index do |cmd, index|
      status = spinner_status[index]
      color = case status
              when 'success'
                COLORS[:green]
              when 'fail'
                COLORS[:red]
              else
                COLORS[:white]  # Still running
              end

      command_name = command_names[index]
      command_display = "#{color}#{command_name}#{COLORS[:reset]}"

      line += "#{index == 0 ? '' : '♦'}#{command_display}"
    end

    # Print the single-line spinner and command status
    print "\r#{line}"
    STDOUT.flush  # Ensure real-time display of the spinner
  end

  # Store the commands being run so they can be accessed by the spinner
  def self.all_commands
    @all_commands
  end
end
