#!/usr/bin/env ruby
require 'pty'
require 'io/console'
require_relative 'gpush_error' # Import the custom error handling

class Command
  attr_reader :name, :shell, :output
  attr_accessor :status

  COLORS = {
    green: "\e[32m",
    red: "\e[31m",
    white: "\e[37m",
    bold: "\e[1m",
    reset: "\e[0m"
  }.freeze

  SPINNER = ['|', '/', '-', '\\'].freeze

  def initialize(command_dict, index: 0, verbose: false)
    @shell = command_dict['shell'] || raise(GpushError, 'Command must have a "shell" field.')
    @name = command_dict['name'] || @shell
    @index = index
    @status = 'not started'
    @output = []
  end

  def run(verbose: false)
    exit_status = nil
    @status = 'working'
    spinner_thread = start_spinner

    begin
      # Use PTY for real-time command output, capturing both stdout and stderr
      PTY.spawn(@shell) do |stdout, _stdin, pid|
        stdout.each do |line|
          if verbose
            puts line  # Print directly if verbose is true
          else
            @output << line  # Collect command output into @output
          end
        end

        # Wait for the child process to exit and capture its status
        _, exit_status = Process.wait2(pid)
      end

      @status = exit_status&.success? ? 'success' : 'fail'
    rescue PTY::ChildExited
      @status = 'fail'
    ensure
      @spinner_running = false
      spinner_thread.join  # Ensure spinner stops before ending
    end

    [@output.join, @status]  # Return output and status for later use
  end

  def spinner
    return "✓" if status === 'success'
    return "✗" if status === 'fail'
    SPINNER[output.length % SPINNER.size]
  end

  private

  def start_spinner
    @spinner_running = true
    Thread.new do
      i = 0
      while @spinner_running
        self.class.print_single_line_spinner(Command.all_commands)
        i = (i + 1) % SPINNER.size
        sleep 0.3
      end
      self.class.print_single_line_spinner(Command.all_commands)  # Ensure final status is printed after spinner stops
    end
  end

  # Class method to run commands in parallel and show summary
  def self.run_in_parallel(commands, verbose: false)
    errors = 0  # Start error counter
    @all_commands = commands.map.with_index { |cmd, index| new(cmd, index:, verbose:) }

    threads = @all_commands.map.with_index do |command, index|
      Thread.new do
        begin
          output, status = command.run(verbose:)  # Capture the output and status

          # If command failed, increment the error counter
          errors += 1 if status == 'fail'
        rescue GpushError
          command.status = 'fail'
          errors += 1  # Increment errors if an exception occurs
        end
      end
    end

        # Store the existing handler for SIGINT (if any)
    default_int_handler = Signal.trap("INT") do
      puts "\nCtrl-C detected, attempting to stop gracefully..."
      @all_commands.each do |command|
        puts "========== Output for: #{command.name} =========="
        puts command.output
        puts "\n"
      end

      # If there was a previous handler, call it (this is equivalent to calling `super` in a signal trap)
      default_int_handler.call if default_int_handler.respond_to?(:call)

      exit 1  # Exit the program after handling the signal
    end

    # Spinner summary box with a single line spinner
    spinner_thread = Thread.new do
      i = 0
      while threads.any?(&:alive?)
        print_single_line_spinner(@all_commands)
        i = (i + 1) % SPINNER.size
        sleep 0.3  # Limit the summary box refresh rate
      end
    end

    # Wait for all threads to complete
    threads.each(&:join)
    spinner_thread.kill  # Stop the spinner thread
    # Final spinner print with completed statuses
    print_single_line_spinner(@all_commands)  # Show all tests in their final state

    # Final output after all threads are done
    puts ""
    @all_commands.each do |command|
      next if command.status == 'success' || verbose  # Skip if verbose because outputs will be printed in real-time
      puts "#{COLORS[:bold]}========== Output for: #{command.name} ==========#{COLORS[:reset]}"
      puts command.output  # Print the buffered output for failed commands.
      puts "\n\n"
    end

    # Print overall summary
    puts "\n#{COLORS[:bold]}Summary#{COLORS[:reset]}"
    @all_commands.each do |cmd|
      status_color = cmd.status == 'success' ? COLORS[:green] : COLORS[:red]  # Green for success, red for fail
      puts "#{cmd.name}: #{status_color}#{cmd.status.upcase}#{COLORS[:reset]}"
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
    "#{command[0...max_length - 4]}... "  # Truncate and add ellipsis
  end

  def self.print_single_line_spinner(commands)
    command_names = commands.map { |command| "[#{command.spinner}]#{command.name}  " }
    command_names.map! { |name| name[0..-2] } if over_width?(command_names)
    command_names.map! { |name| "#{name.gsub(/\s/,'')} " } if over_width?(command_names)
    command_names.map! { |name| name[1] + name[3..-1] } if over_width?(command_names) # remove the [] brackets
    command_names.map! { |cmd| truncate_command_name(cmd, terminal_width / command_names.size) } if over_width?(command_names)

    line = commands.map.with_index do |cmd, index|
      color = case cmd.status
              when 'success'
                COLORS[:green]
              when 'fail'
                COLORS[:red]
              else
                COLORS[:white]  # Still running
              end

      command_name = command_names[index]
      command_display = "#{color}#{command_name}#{COLORS[:reset]}"
    end.join

    # Print the single-line spinner and command status
    print "\r#{' ' * terminal_width}"  # Clear the line
    print "\r#{line}"
    STDOUT.flush  # Ensure real-time display of the spinner
  end

  def self.over_width?(command_names)
    command_names.map(&:size).sum > terminal_width
  end

  # Store the commands being run(verbose: false) so they can be accessed by the spinner
  def self.all_commands
    @all_commands
  end
end
