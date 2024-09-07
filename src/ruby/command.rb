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

  def initialize(command_dict)
    @shell = command_dict['shell'] || raise(GpushError, 'Command must have a "shell" field.')
    @name = command_dict['name'] || @shell
    @status = 'not started'
    @output = ""
  end

  def run
    puts "\n#{COLORS[:bold]}Running: #{@name}#{COLORS[:reset]}"
    @status = 'working'
    spinner_thread = start_spinner

    begin
      PTY.spawn(@shell) do |stdout, _stdin, pid|
        begin
          stdout.each do |line|
            handle_output(line)
          end
        rescue Errno::EIO
          # End of input
        end

        # Wait for the child process to exit and capture its status
        _, exit_status = Process.wait2(pid)

        # Check if the command exited successfully
        if exit_status.success?
          @status = 'success'
          pass_fail(@name, true)
        else
          @status = 'fail'
          pass_fail(@name, false)
        end
      end
    rescue PTY::ChildExited
      @status = 'fail'
      pass_fail(@name, false)
    ensure
      @spinner_running = false
      spinner_thread.join  # Ensure spinner stops before ending
    end
  end

  private

  def pass_fail(name, passed)
    puts "\n#{name}: #{COLORS[passed ? :green : :red]}[#{passed ? 'PASS' : 'FAIL'}]#{COLORS[:reset]}"
  end

  def handle_output(line)
    @output << line
    print line # Print the output to the terminal immediately to retain color
  end

  def start_spinner
    @spinner_running = true
    Thread.new do
      i = 0
      while @spinner_running
        print "\r#{SPINNER[i]}"
        i = (i + 1) % SPINNER.size
        sleep 0.1
      end
      print "\r"  # Clear spinner
    end
  end

  # Class method to run commands in parallel
  def self.run_in_parallel(commands)
    threads = commands.map do |cmd_dict|
      Thread.new do
        command = Command.new(cmd_dict)
        begin
          command.run
          cmd_dict[:status] = 'success' if command.status == 'success'
          cmd_dict[:status] = 'fail' if command.status == 'fail'
        rescue GpushError
          cmd_dict[:status] = 'fail'  # Store failure in the hash if an error occurs
        end
      end
    end

    # Wait for all threads to complete
    threads.each(&:join)

    # Print summary
    puts "\n#{COLORS[:bold]}Summary#{COLORS[:reset]}"
    commands.each do |cmd|
      status_color = cmd[:status] == 'success' ? COLORS[:green] : COLORS[:red]  # Green for success, red for fail
      puts "#{cmd['name'] || cmd['shell']}: #{status_color}#{cmd[:status].upcase}#{COLORS[:reset]}"
    end
    puts ""

    errors = commands.count { |cmd| cmd[:status] != 'success' }
    errors
  end
end
