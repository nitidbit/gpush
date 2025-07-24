require_relative "command"
require_relative "config_helper"
require_relative "exit_helper"

module GpushRun
  class << self
    def go(args:, options:)
      if options.any?
        puts "Unexpected option(s): #{options.keys.join(", ")}"
        puts "gpush run does not accept any options."
        puts "Run 'gpush --help' for usage information."
        ExitHelper.exit 1
      elsif args.nil? || args.empty?
        puts "Enter a command to run (e.g., gpush run test_name)"
        ExitHelper.exit 1
      else
        run_one_command_and_exit(args.join(" "))
      end
    end

    private

    def normalize_command_name(command_input)
      command_input.strip.gsub(/[\s_-]/, "").downcase
    end

    def run_one_command_and_exit(command_input)
      cmd_dict =
        ConfigHelper.parse_config["parallel_run"].find do |cmd|
          normalize_command_name(cmd["name"] || cmd["shell"]) ==
            normalize_command_name(command_input)
        end

      if cmd_dict
        command = Command.new(cmd_dict, verbose: true, prefix_output: false)
        message = "Running command: #{command.name}"
        puts "#{Command::COLORS[:bold]}========== #{message} ==========#{Command::COLORS[:reset]}"
        command.run
        puts ""
        puts command.final_summary
        ExitHelper.exit command.success? ? 0 : 1
      else
        puts "Command not found: #{command_input}"
        puts "gpush run looks for a command in the parallel_run section of the config file."
        ExitHelper.exit 1
      end
    end
  end
end
