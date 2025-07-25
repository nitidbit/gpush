require_relative "command"
require_relative "config_helper"
require_relative "exit_helper"
require_relative "gpush_error"

module GpushFix
  def self.go(args:, options:)
    config_file = options.delete(:config_file)

    if options.any?
      puts "Unexpected option(s): #{options.keys.join(", ")}"
      puts "Run 'gpush --help' for usage information."
      ExitHelper.exit(1)
    elsif args.any?
      puts "Unexpected argument(s): #{args.join(", ")}"
      puts "gpush fix does not accept any arguments."
      puts "Run 'gpush --help' for usage information."
      ExitHelper.exit(1)
    end

    config = ConfigHelper.parse_config(config_file)

    if config["fix"].nil?
      puts "No fix section found in config file"
      ExitHelper.exit(1)
    end

    if config["fix"].empty?
      puts "Fix section is empty"
      ExitHelper.exit(1)
    end

    config["fix"].each do |cmd_dict|
      command = Command.new(cmd_dict, verbose: true, prefix_output: false)
      command.run
    end

    ExitHelper.exit(0)
  end
end
