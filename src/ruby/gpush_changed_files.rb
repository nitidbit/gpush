#!/usr/bin/env ruby
# frozen_string_literal: true

require "English"
require_relative "gpush_version"
require_relative "git_helper"
require_relative "gpush_options_parser"
require_relative "exit_helper"

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

  def diff_base_ref
    "origin/#{resolved_diff_branch_name}"
  end

  def all_changed_files
    diff_cmd = diff_command(resolved_diff_branch_name)
    stdout, status = Open3.capture2(diff_cmd)
    return stdout.split("\n") if status.success?

    raise GpushError,
          "Failed to run diff command: #{diff_cmd}, exited with status: #{status}"
  end

  def format_changed_files(files = all_changed_files)
    # Process within the git root directory
    Dir.chdir(GitHelper.git_root_dir) do
      unless @options[:include_deleted_files]
        files.select! { |filename| File.exist? filename }
      end

      # Apply glob pattern filtering if specified
      if @options[:pattern]
        valid_glob_pattern?(@options[:pattern])
        matched_by_pattern = Dir.glob(@options[:pattern])
        files.select! { |file| matched_by_pattern.include?(file) }
      end

      if @options[:root_dir]
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

  def diff_command(branch)
    "git diff --name-only origin/#{branch}"
  end

  private

  def resolved_diff_branch_name
    branch_name = ENV.fetch("GPUSH_BRANCH", nil) || GitHelper.local_branch_name

    if GitHelper.branch_exists_on_origin?(branch_name)
      log("Checking diff for branch: origin/#{branch_name}")
      return branch_name
    end

    fallback_branch =
      @options[:fallback_branches].find do |fallback|
        GitHelper.branch_exists_on_origin?(fallback)
      end

    if fallback_branch
      log "Branch #{branch_name} not found on origin. Falling back to origin/#{fallback_branch}."
      return fallback_branch
    end

    puts "Branch not found on origin and no fallback branches available."
    ExitHelper.exit(2)
  end

  def log(message)
    puts message if @options[:verbose]
  end

  def valid_glob_pattern?(pattern)
    # Ensure the pattern is not empty or nil
    if pattern.nil? || pattern.strip.empty?
      raise GpushError, "Invalid pattern: pattern cannot be empty or nil"
    end

    if pattern.include?(" ")
      raise GpushError, "Invalid pattern: contains spaces"
    end

    # Ensure braces `{}` are balanced
    check_balanced(pattern, "{", "}")

    # Ensure brackets `[]` are balanced
    check_balanced(pattern, "[", "]")

    # Ensure no consecutive directory separators (e.g., `//`)
    if pattern.include?("//")
      raise GpushError, "Invalid pattern: contains consecutive slashes"
    end

    # Ensure no empty braces `{}` or brackets `[]`
    if pattern.match?(/\{\}/) || pattern.match?(/\[\]/)
      raise GpushError, "Invalid pattern: contains empty braces or brackets"
    end

    true # Pattern is valid
  end

  def check_balanced(pattern, open_char, close_char)
    open_count = pattern.count(open_char)
    close_count = pattern.count(close_char)

    return unless open_count != close_count
    raise GpushError,
          "Invalid pattern: unmatched #{open_char} and #{close_char}"
  end
end

if __FILE__ == $PROGRAM_NAME
  begin
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
      )

    output = GpushChangedFiles.new(options).format_changed_files
    puts output if output.length.positive?
    exit output.length.positive? ? 0 : 1
  rescue GpushError => e
    ExitHelper.exit_with_error(e)
  end
end
