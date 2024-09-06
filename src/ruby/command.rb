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

  def initialize(command_dict, working_directory)
    @shell = command_dict['shell'] || raise(GpushError, 'Command must have a "shell" field.')
    @shell = "cd \"#{working_directory}\" && #{@shell}" # Use the captured working directory
    @name = command_dict['name'] || @shell
    @status = 'not started'
    @output = ""
  end

  def run
    puts "\n#{COLORS[:bold]}Running: #{@name}#{COLORS[:reset]}"
    @status = 'working'

    begin
      PTY.spawn(@shell) do |stdout, _stdin, _pid|
        begin
          stdout.each do |line|
            handle_output(line)
          end
        rescue Errno::EIO
          # End of input
        end
      end
      @status = 'success'
       pass_fail(@name, true)
    rescue PTY::ChildExited
      @status = 'fail'
      pass_fail(@name, false)
    end
  end

  private

  def pass_fail(name, passed)
    puts "\n#{name}: #{COLORS[passed ? :green : red]}[#{passed ? 'PASS' : 'FAIL'}]#{COLORS[:reset]}"  # Green color for pass
  end

  def handle_output(line)
    @output << line
    print line # Print the output to the terminal immediately to retain color
  end

  # Class method to run commands in parallel
  def self.run_in_parallel(commands, working_directory)
    threads = commands.map do |cmd_dict|
      Thread.new do
        command = Command.new(cmd_dict, working_directory)
        begin
          command.run
          cmd_dict[:status] = 'success'  # Store status in the hash
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
