#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "yaml"

class GpushOptionsParser
  CONFIG_FILE = %w[gpushrc.yml gpushrc.yaml].freeze

  def self.parse(
    arguments,
    config_prefix:,
    option_definitions:,
    required_options:
  )
    options = {}

    # Find the config file by searching from the current directory upwards
    config_file_path = find_config_file

    if config_file_path
      # Load options from the config file if it exists
      config_from_file = YAML.load_file(config_file_path)
      unless config_from_file.is_a?(Hash)
        raise "Invalid configuration file format. Must be a YAML hash."
      end
      if config_from_file[config_prefix]
        options.merge! config_from_file[config_prefix].transform_keys(&:to_sym)
      end
    else
      puts "Config file '#{CONFIG_FILE}' not found. Proceeding without it."
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

  def self.find_config_file
    current_dir = Dir.pwd
    while current_dir != "/"
      CONFIG_FILE.each do |config_filename|
        config_file = File.join(current_dir, config_filename)
        return config_file if File.exist?(config_file)
      end
      current_dir = File.expand_path("..", current_dir) # Move up one directory
    end
    # Return nil if the config file is not found
  end
end
