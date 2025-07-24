#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "yaml"
require_relative "gpush_error"
require_relative "exit_helper"
require_relative "config_helper"

class GpushOptionsParser
  def self.parse(
    arguments,
    config:,
    option_definitions:,
    required_options:,
    config_prefix: nil
  )
    subconfig = config_prefix ? config[config_prefix] : config
    options = {
      **(subconfig || {}).transform_keys(&:to_sym),
      **option_definitions,
    }

    # Parse command-line arguments
    OptionParser
      .new do |opts|
        opts.banner = "Usage: script.rb [options]"
        option_definitions.call(opts, options)
        opts.on("-h", "--help", "Prints this help") do
          puts opts
          ExitHelper.exit 1
        end
      end
      .parse!(arguments)

    # Validate required options
    missing_options = required_options.select { |opt| options[opt].nil? }
    unless missing_options.empty?
      puts "Missing required options: #{missing_options.map { |opt| "--#{opt.to_s.tr("_", "-")}" }.join(", ")}"
      ExitHelper.exit 1
    end

    options
  end

  def self.check_version(current_version, config)
    return if current_version == "local-development"

    required_version = [config["gpush_version"]].flatten

    requirement = Gem::Requirement.new(required_version)
    current_version = Gem::Version.new(current_version)

    return if requirement.satisfied_by?(current_version)

    raise GpushError,
          "Your config file specifies version #{required_version.join(", ")}. You have #{current_version}.\n\nRun 'brew update && brew upgrade gpush' to update."
  end
end
