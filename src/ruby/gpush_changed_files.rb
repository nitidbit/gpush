#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative File.join(__dir__, "gpush_options_parser")

class GpushChangedFiles
  DEFAULT_FALLBACK_BRANCHES = %w[main master].freeze

  DEFAULT_OPTIONS = {
    root_dir: nil,
    fallback_branches: DEFAULT_FALLBACK_BRANCHES,
    verbose: false,
    separator: " ",
    pattern: nil,
    include_deleted_files: false,
  }.freeze

  def self.git_root_dir
    root_dir = `git rev-parse --show-toplevel`.strip
    return root_dir if $?.success?
      
    
      raise "Not inside a Git repository"
    
  end

  def initialize(options = {})
    @options = DEFAULT_OPTIONS.merge(options)

    # Use git_root_dir as a fallback if root_dir is not set
    @options[:root_dir] ||= self.class.git_root_dir

    validate_options
    log("Starting GpushChangedFiles with options:")
    log(@options.map { |k, v| "  #{k}: #{v}" }.join("\n"))
    log("")
  end

  def git_changed_files
    branch_name = `git rev-parse --abbrev-ref HEAD`.strip

    # Determine which branch to use for the diff
    if branch_exists_on_origin?(branch_name)
      diff_cmd = diff_command(branch_name, @options[:pattern])
    else
      fallback_branch =
        @options[:fallback_branches].find do |fallback|
          branch_exists_on_origin?(fallback)
        end

      if fallback_branch
        log "Branch #{branch_name} not found on origin. Falling back to origin/#{fallback_branch}."
        diff_cmd = diff_command(fallback_branch, @options[:pattern])
      else
        puts "Branch not found on origin and no fallback branches available."
        exit 2
      end
    end

    # Run the diff command and capture the output
    Dir.chdir(@options[:root_dir]) do
      result = `#{diff_cmd}`.split("\n")
      if $?.success?
        # Filter out deleted files if the option is not set
        return result if @options[:include_deleted_files]

        result.select { |fn| File.exist? File.join(@options[:root_dir], fn) }
      else
        puts "Error executing git diff command."
        exit 3
      end
    end
  end

  def format_changed_files(files = git_changed_files)
    files.join(@options[:separator])
  end

  def diff_command(branch, patterns = nil)
    # Start with the base diff command
    log("Checking diff for branch: origin/#{branch}")
    command = "git diff --name-only origin/#{branch}"

    # If patterns are provided, append them immediately after the branch reference
    if patterns
      pattern_list = patterns.split(" ")
      # No need to escape the patterns; pass them directly
      command += " -- #{pattern_list.join(" ")}"
    end

    command
  end

  private

  def validate_options
    return if @options[:root_dir]
      puts "Error: root_dir is required."
      exit 4
    
  end

  def log(message)
    puts message if @options[:verbose]
  end

  def branch_exists_on_origin?(branch_name)
    # Use git ls-remote to check if the branch exists on origin
    result = `git ls-remote --heads origin #{branch_name}`.strip
    !result.empty?
  end
end

if __FILE__ == $PROGRAM_NAME
  # Use GpushOptionsParser to parse command-line arguments
  options =
    GpushOptionsParser.parse(
      ARGV,
      config_prefix: "gpush_changed_files",
      option_definitions:
        lambda do |opts, options|
          opts.on("--root-dir ROOT_DIR", "Specify root directory") do |v|
            options[:root_dir] = v
          end
          opts.on(
            "--fallback-branches x,y,z",
            Array,
            "Specify fallback branches",
          ) { |v| options[:fallback_branches] = v }
          opts.on("--verbose", "Enable verbose output") do
            options[:verbose] = true
          end
          opts.on("--separator SEPARATOR", "Specify separator") do |v|
            options[:separator] = v
          end
          opts.on(
            "--pattern PATTERN",
            "Filter files by pattern (e.g., *.rb *.js)",
          ) { |v| options[:pattern] = v }
          opts.on("--include-deleted-files", "Include deleted files") do
            options[:include_deleted_files] = true
          end
        end,
      required_options: [], # No required options
    )

  # Create the GpushChangedFiles instance with the parsed options
  changed_files_finder = GpushChangedFiles.new(options)

  # Find the changed files and output the result
  changed_files = changed_files_finder.git_changed_files
  output = changed_files_finder.format_changed_files(changed_files)
  puts output if changed_files.any?
  exit changed_files.any? ? 0 : 1
end
