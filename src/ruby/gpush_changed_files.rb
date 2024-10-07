#!/usr/bin/env ruby
# frozen_string_literal: true

require "English"
require_relative File.join(__dir__, "gpush_options_parser")
require_relative File.join(__dir__, "git_helper")
require "byebug"

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

  def initialize(options = {})
    @options = DEFAULT_OPTIONS.merge(options)

    log("Starting GpushChangedFiles with options:")
    log(@options.map { |k, v| "  #{k}: #{v}" }.join("\n"))
    log("")
  end

  def all_changed_files
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
    result = `#{diff_cmd}`.split("\n")
    return result if $CHILD_STATUS.success?
    puts "Error executing git diff command."
    exit 3
  end

  def format_changed_files(files = all_changed_files)
    if @options[:root_dir]
      # in a block within the git root directory
      Dir.chdir(GitHelper.git_root_dir) do
        unless @options[:include_deleted_files]
          files.select! { |filename| File.exist? filename }
        end

        # check that the root directroy is a valid directory
        unless File.directory?(@options[:root_dir])
          raise GpushError,
                "Root directory #{@options[:root_dir]} is not a valid directory."
        end

        # filter out files that are not in the root directory
        files.select! { |file| file.start_with?(@options[:root_dir]) }
        # remove the root directory from the file paths
        files.map! { |file| file.sub(%r{^#{@options[:root_dir]}/?}, "") }
      end
    end
    files.join(@options[:separator])
  end

  def diff_command(branch, patterns = nil)
    # Start with the base diff command
    log("Checking diff for branch: origin/#{branch}")
    command = "git diff --name-only origin/#{branch}"

    # If patterns are provided, append them immediately after the branch reference
    if patterns
      pattern_list = patterns.split
      # No need to escape the patterns; pass them directly
      command += " -- #{pattern_list.join(" ")}"
    end
    command
  end

  private

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
  begin
    # Use GpushOptionsParser to parse command-line arguments
    options =
      GpushOptionsParser.parse(
        ARGV,
        config_prefix: "gpush_changed_files",
        option_definitions:
          lambda do |opts, parsing_options|
            opts.on("--root-dir ROOT_DIR", "Specify root directory") do |v|
              parsing_options[:root_dir] = v
            end
            opts.on(
              "--fallback-branches x,y,z",
              Array,
              "Specify fallback branches",
            ) { |v| parsing_options[:fallback_branches] = v }
            opts.on("--verbose", "Enable verbose output") do
              parsing_options[:verbose] = true
            end
            opts.on("--separator SEPARATOR", "Specify separator") do |v|
              parsing_options[:separator] = v
            end
            opts.on(
              "--pattern PATTERN",
              "Filter files by pattern (e.g., *.rb *.js)",
            ) { |v| parsing_options[:pattern] = v }
            opts.on("--include-deleted-files", "Include deleted files") do
              parsing_options[:include_deleted_files] = true
            end
          end,
        required_options: [], # No required options
      )

    # Find the changed files and output the result
    output = GpushChangedFiles.new(options).format_changed_files
    puts output if output.length.positive?
    exit output.length.positive? ? 0 : 1
  rescue GpushError => e
    GitHelper.exit_with_error(e)
  end
end
