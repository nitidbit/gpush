#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "yaml"

class GpushOptionsParser
  CONFIG_FILE = "gpushrc.yml"

  def self.parse(arguments, option_definitions, required_options)
    options = {}

    # Load options from the config file if it exists
    options.merge!(YAML.load_file(CONFIG_FILE)) if File.exist?(CONFIG_FILE)

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
