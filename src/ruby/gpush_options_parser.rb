#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "yaml"

class GpushOptionsParser
  CONFIG_FILE = "gpushrc.yml"

  def self.parse(arguments, config_prefix:, option_definitions:, required_options:)
    options = {}

    # Load options from the config file if it exists
    if File.exist?(CONFIG_FILE)
      config_from_file = YAML.load_file(CONFIG_FILE)
      if !config_from_file.is_a?(Hash)
        raise "Invalid configuration file format. Must be a YAML hash."
      end
      options.merge!(config_from_file)
    end

    # Parse command-line arguments
    OptionParser
      .new do |opts|
        opts.banner = "Usage: script.rb [options]"
        option_definitions.call(opts, options)
        opts.on("-h", "--help", "Prints this help") do
          puts opts
          exit 1
        end
      end
      .parse!(arguments)

    # Validate required options
    missing_options = required_options.select { |opt| options[opt].nil? }
    unless missing_options.empty?
      puts "Missing required options: #{missing_options.map { |opt| "--#{opt.to_s.tr("_", "-")}" }.join(", ")}"
      exit 1
    end

    options
  end
end
