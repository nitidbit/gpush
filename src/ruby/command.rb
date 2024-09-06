require 'open3'
require_relative 'gpush_error' # Import the custom error handling

class Command
  attr_reader :name, :shell, :status

  def initialize(command_dict, working_directory)
    @shell = command_dict['shell'] || raise(GpushError, 'Command must have a "shell" field.')
    # Ensure the shell runs from the directory where the script was executed
    @shell = "cd \"#{working_directory}\" && #{@shell}" # Use the captured working directory
    @name = command_dict['name'] || @shell
    @status = 'not started'
    @output = ""
  end

  def run
    puts "\nRunning: #{@name}"
    @status = 'working'

    # Use Open3 to capture stdout, stderr, and exit status
    system(@shell) do |stdin, stdout, stderr, wait_thr|
      # Read stdout and stderr in parallel
      Thread.new { stdout.each { |line| handle_output(line) } }
      Thread.new { stderr.each { |line| handle_output(line) } }

      exit_status = wait_thr.value

      if exit_status.success?
        @status = 'success'
      else
        @status = 'fail'
        raise GpushError, "Command #{@name} failed with exit code #{exit_status.exitstatus}."
      end
    end
  end

  private

  def handle_output(line)
    @output << line
    print line # Print the output to the terminal immediately to retain color
    puts "======"
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

    # Check for errors by counting failed commands
    errors = commands.count { |cmd| cmd[:status] != 'success' }
    errors
  end
end
