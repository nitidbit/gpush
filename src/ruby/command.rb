require 'pty'
require_relative 'gpush_error' # Import the custom error handling

class Command
  attr_reader :name, :shell, :status

  COLORS = {
    green: "\e[32m",
    red: "\e[31m",
    bold: "\e[1m",
    reset: "\e[0m"
  }.freeze

  SPINNER = ['|', '/', '-', '\\'].freeze
  SEPARATOR = "------------------------------------------------------".freeze

  def initialize(command_dict, index, spinner_status)
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
      PTY.spawn(@shell) do |stdout, _stdin, pid|
        begin
          stdout.each do |line|
            @output << line  # Collect command output, buffer it for printing at the end
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

    # Update spinner status to pass/fail status and stop printing
    @spinner_status[@index] = @status == 'success' ? '[PASS]' : '[FAIL]'

    [@output.join, @status]  # Return output and status for later use
  end

  private

  def start_spinner
    @spinner_running = true
    Thread.new do
      i = 0
      while @spinner_running
        @spinner_status[@index] = SPINNER[i]  # Update spinner status
        i = (i + 1) % SPINNER.size
        print_summary_line
        sleep 0.3  # Reduced spinner refresh rate
      end
      # Ensure final status is printed after spinner stops
      print_summary_line
    end
  end

  def print_summary_line
    print "\r#{name}: #{@spinner_status[@index]}"
  end

  # Class method to run commands in parallel and show summary
  def self.run_in_parallel(commands)
    errors = 0
    spinner_status = Array.new(commands.size, ' ')  # Initialize spinner status for each command

    threads = commands.map.with_index do |cmd_dict, index|
      Thread.new do
        command = Command.new(cmd_dict, index, spinner_status)
        begin
          output, status = command.run  # Capture the output and status
          cmd_dict[:status] = status == 'success' ? 'success' : 'fail'
          cmd_dict[:output] = output  # Store output for later use
        rescue GpushError
          cmd_dict[:status] = 'fail'  # Store failure in the hash if an error occurs
          errors += 1
        end
      end
    end

    # Wait for all threads to complete
    threads.each(&:join)

    # Print buffered output for all commands once they're done
    puts SEPARATOR
    commands.each do |cmd|
      puts "#{COLORS[:bold]}Output for: #{cmd['name'] || cmd['shell']}#{COLORS[:reset]}"
      puts cmd[:output]  # Print the buffered output
      puts SEPARATOR
    end

    # Print overall summary
    puts "\n#{COLORS[:bold]}Summary#{COLORS[:reset]}"
    commands.each do |cmd|
      status_color = cmd[:status] == 'success' ? COLORS[:green] : COLORS[:red]  # Green for success, red for fail
      puts "#{cmd['name'] || cmd['shell']}: #{status_color}#{cmd[:status].upcase}#{COLORS[:reset]}"
    end
    puts ""

    errors
  end
end
