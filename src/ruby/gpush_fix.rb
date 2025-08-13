require_relative "command"
require_relative "config_helper"
require_relative "exit_helper"
require_relative "gpush_error"

module GpushFix
  def self.go(args:, options:)
    if args.any?
      puts "Unexpected argument(s): #{args.join(", ")}"
      puts "gpush fix does not accept any arguments."
      puts "Run 'gpush --help' for usage information."
      ExitHelper.exit(1)
    end

    if options[:fix].nil?
      puts "No fix section found in config file"
      ExitHelper.exit(1)
    end

    if options[:fix].empty?
      puts "Fix section is empty"
      ExitHelper.exit(1)
    end

    commands_succeeded =
      options[:fix].map do |cmd_dict|
        command = Command.new(cmd_dict, verbose: true, prefix_output: false)
        command.run
        command.success?
      end

    ExitHelper.exit(commands_succeeded.all? ? 0 : 1)
  end

  def self.option_definitions
    lambda do |opts, parsing_options|
      # no options for fix
    end
  end

  def self.required_options = %i[]
end
