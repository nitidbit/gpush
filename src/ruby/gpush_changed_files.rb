#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative File.join(__dir__, "gpush_options_parser")

class GpushChangedFiles
  DEFAULT_FALLBACK_BRANCHES = %w[main master].freeze

  OPTIONS = {
    root_dir: nil,
    fallback_branches: DEFAULT_FALLBACK_BRANCHES,
    verbose: false,
    separator: " ",
    pattern: nil
  }.freeze

  def self.git_root_dir
    root_dir = `git rev-parse --show-toplevel`.strip
    if $?.success?
      return root_dir
    else
      raise "Not inside a Git repository"
    end
  end

  def initialize(options = {})
    @options = OPTIONS.merge(options)

    # Use git_root_dir as a fallback if root_dir is not set
    @options[:root_dir] ||= self.class.git_root_dir

    validate_options
  end

  def git_changed_files
    branch_name = `git rev-parse --abbrev-ref HEAD`.strip
    origin_branch = "origin/#{branch_name}"

    # Determine which branch to use for the diff
    if branch_exists?(branch_name)
      diff_cmd = diff_command(branch_name, @options[:pattern])
    else
      fallback_branch = @options[:fallback_branches].find { |fallback| branch_exists?(fallback) }

      if fallback_branch
        diff_cmd = diff_command(fallback_branch, @options[:pattern])
        log("Branch not found on origin. Falling back to origin/#{fallback_branch}.")
      else
        puts "Branch not found on origin and no fallback branches available."
        exit 1
      end
    end

    # Run the diff command and capture the output
    Dir.chdir(@options[:root_dir]) do
      result = `#{diff_cmd}`.split("\n")
      if $?.success?
        return result
      else
        puts "Error executing git diff command."
        exit 1
      end
    end
  end

  def format_changed_files(files = git_changed_files)
    files.join(@options[:separator])
  end

  def diff_command(branch, patterns = nil)
    # Start with the base diff command
    command = "git diff --name-status origin/#{branch}"

    # If patterns are provided, append them immediately after the branch reference
    if patterns
      pattern_list = patterns.split(' ')
      # No need to escape the patterns; pass them directly
      command += " -- #{pattern_list.join(' ')}"
    end

    # Continue with grep and awk to filter out deleted files
    command += " | grep -v '^D' | awk '{print $2}'"

    command
  end

  private

  def validate_options
    unless @options[:root_dir]
      puts "Error: root_dir is required."
      exit 1
    end
  end

  def log(message)
    puts message if @options[:verbose]
  end

  def branch_exists?(branch_name)
    # Use git ls-remote to check if the branch exists on origin
    result = `git ls-remote --heads origin #{branch_name}`.strip
    !result.empty?
  end
end

if __FILE__ == $PROGRAM_NAME
  # Use GpushOptionsParser to parse command-line arguments
  options = GpushOptionsParser.parse(
    ARGV,
    config_prefix: "gpush_changed_files",
    option_definitions: lambda do |opts, options|
      opts.on('--root-dir ROOT_DIR', 'Specify root directory') { |v| options[:root_dir] = v }
      opts.on('--fallback-branches x,y,z', Array, 'Specify fallback branches') { |v| options[:fallback_branches] = v }
      opts.on('--verbose', 'Enable verbose output') { options[:verbose] = true }
      opts.on('--separator SEPARATOR', 'Specify separator') { |v| options[:separator] = v }
      opts.on('--pattern PATTERN', 'Filter files by pattern (e.g., *.rb *.js)') { |v| options[:pattern] = v }
    end,
    required_options: [] # No required options
  )

  # Create the GpushChangedFiles instance with the parsed options
  changed_files_finder = GpushChangedFiles.new(options)

  # Find the changed files and output the result
  changed_files = changed_files_finder.git_changed_files
  output = changed_files_finder.format_changed_files(changed_files)
  puts output if changed_files.any?
end
