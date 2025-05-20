#!/usr/bin/env ruby
require "json"

module VersionChecker
  # Main method to check for updates and print a message if a new version is available
  def self.print_message_if_new_version(current_version)
    return if current_version == "local-development" # Skip check for dev versions
    return unless homebrew_installed?

    latest_stable = get_latest_version
    return unless valid_version?(latest_stable)
    return unless valid_version?(current_version)

    return unless newer_version_available?(current_version, latest_stable)
    print_update_message(current_version, latest_stable)
  end

  # Check whether Homebrew is installed
  def self.homebrew_installed?
    system("which brew > /dev/null 2>&1")
  end

  # Get the latest version from Homebrew
  def self.get_latest_version
    latest_version = `brew info gpush --json=v1 2>/dev/null`.strip
    return nil if latest_version.empty?

    latest_info = JSON.parse(latest_version)
    if latest_info.empty? || !latest_info[0] || !latest_info[0]["versions"] ||
         !latest_info[0]["versions"]["stable"]
      return nil
    end

    latest_info[0]["versions"]["stable"]
  rescue StandardError
    nil
  end

  # Check if a version string is valid
  def self.valid_version?(version)
    !version.nil? && !version.empty?
  end

  # Check if a newer version is available
  def self.newer_version_available?(current_version, latest_stable)
    current_version_obj = Gem::Version.new(current_version)
    latest_version_obj = Gem::Version.new(latest_stable)

    latest_version_obj > current_version_obj
  rescue ArgumentError
    false
  end

  # Print the update message
  def self.print_update_message(current_version, latest_stable)
    puts "\n💎 A new version of gpush is available: #{latest_stable} (you have #{current_version})"
    puts "💎 Update with:"

    # Define color codes
    green = "\e[32m"
    bold = "\e[1m"
    reset = "\e[0m"

    # Print the command in green and bold
    puts "    #{green}#{bold}brew update && brew upgrade gpush#{reset}"
  end
end
