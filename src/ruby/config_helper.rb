require "yaml"
require_relative "git_helper"

module ConfigHelper
  CONFIG_NAMES = %w[gpushrc.yml gpushrc.yaml].freeze

  class << self
    def config_file_path(config_file = nil)
      if config_file
        found_config_file = File.join(Dir.pwd, config_file)
        unless File.exist?(config_file)
          raise GpushError, "Config file not found: #{config_file}"
        end
      end

      looking_in_dir = Dir.pwd # Start in the current working directory.
      # Continue searching while no config file is found and we haven't reached the root.

      # Check each directory up to and including the root directory
      while !found_config_file && looking_in_dir != "" && looking_in_dir != "/"
        # Check for the config file in the current directory.
        config_name =
          CONFIG_NAMES.find do |path|
            File.exist?(File.join(looking_in_dir, path))
          end

        # If a config file is found, load and return it.
        found_config_file =
          File.join(looking_in_dir, config_name) if config_name
        # Construct the full path to the found config file.

        # Move up one directory level without changing the current working directory.
        looking_in_dir = File.dirname(looking_in_dir)
      end

      return found_config_file if found_config_file

      raise GpushError,
            "Config file not found (Looking for #{CONFIG_NAMES.join(" or ")})"
    end

    def display_config_file_path(config_file = nil)
      config_file_path(config_file).gsub(%r{^#{GitHelper.git_root_dir}/}, "")
    end

    def config_file_dir(config_file = nil)
      File.dirname(config_file_path(config_file))
    end

    def parse_config(config_file = nil, verbose: false)
      full_path = config_file_path(config_file)
      if verbose
        puts "Using config file: #{display_config_file_path(config_file)}"
      end
      config = YAML.load_file full_path
      raise GpushError, "Configuration file is empty!" if config.empty?

      config
    end
  end
end
