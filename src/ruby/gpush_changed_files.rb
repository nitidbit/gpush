#!/usr/bin/env ruby
# frozen_string_literal: true

require "English"
require_relative "gpush_version"
require_relative "git_helper"
require_relative "gpush_options_parser"
require_relative "exit_helper"
require_relative "help_text"

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

  CLI_OPTION_KEYS = %i[
    root_dir
    fallback_branches
    verbose
    separator
    pattern
    include_deleted_files
  ].freeze

  def self.description
    "Print file paths changed vs the remote base ref (see diff-branch)."
  end

  def self.option_definitions
    lambda do |opts, parsing_options|
      opts.banner = <<~BANNER
        #{HelpText.hanging("gpush changed-files: #{description}")}

        Usage:
          gpush changed-files [options]

        Output is space-separated by default. Exits 1 if no files changed.
        If gpushrc defines gpush_changed_files: (fallback branches, etc.),
        those settings apply.

        Options:
      BANNER
      opts.on("--root-dir ROOT_DIR", "Specify root directory") do |v|
        parsing_options[:root_dir] = v
      end
      opts.on(
        "--fallback-branches x,y,z",
        Array,
        "Specify fallback branches",
      ) { |v| parsing_options[:fallback_branches] = v }
      opts.on("-v", "--verbose", "Enable verbose output") do
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
    end
  end

  def self.go(args:, options:)
    if args.any?
      puts "Unexpected argument(s): #{args.join(", ")}"
      puts "Usage: gpush changed-files [options]"
      ExitHelper.exit(1)
    end

    section = options[:gpush_changed_files]
    opts = (section.is_a?(Hash) ? section : {}).transform_keys(&:to_sym)
    output_and_exit(opts.merge(options.slice(*CLI_OPTION_KEYS)))
  end

  def self.output_and_exit(options)
    output = new(options).format_changed_files
    puts output if output.length.positive?
    ExitHelper.exit(output.length.positive? ? 0 : 1)
  end

  # Build an instance from a gpush subcommand's top-level options (i.e. the
  # gpush_changed_files: config section plus a --verbose flag), for
  # subcommands (diff-branch, claude-review) that only need to know the
  # config section's settings rather than accept their own changed-files flags.
  def self.from_options(options)
    section = options[:gpush_changed_files]
    cf_opts = (section.is_a?(Hash) ? section : {}).transform_keys(&:to_sym)
    cf_opts[:verbose] = true if options[:verbose]
    new(cf_opts)
  end

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
  warn "DEPRECATED: gpush_changed_files will be removed in a future version. " \
         "Use 'gpush changed-files' instead."
  begin
    options =
      GpushOptionsParser.parse(
        ARGV,
        config_prefix: "gpush_changed_files",
        option_definitions: GpushChangedFiles.option_definitions,
      )

    GpushChangedFiles.output_and_exit(options)
  rescue GpushError => e
    ExitHelper.exit_with_error(e)
  end
end
