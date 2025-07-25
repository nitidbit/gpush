#!/usr/bin/env ruby
# frozen_string_literal: true

require "English"
require "fileutils"
require "find"
require_relative "exit_helper"
require_relative "git_helper"
require_relative "gpush" # sets version
require_relative "gpush_changed_files"
require_relative "gpush_error"
require_relative "gpush_options_parser"

class GpushGetSpecs
  DEFAULT_OPTIONS = {
    excludes: [],
    min_keyword_length: 3,
    output_separator: " ",
    verbose: false,
  }.freeze

  def initialize(options)
    @options = DEFAULT_OPTIONS.merge(options)
  end

  def find_matching_specs
    if @options[:exclude_words].nil?
      raise GpushError,
            "exclude_words is required. Specify in config file or with --exclude-words cli option"
    end

    changed_files =
      GpushChangedFiles.new(
        root_dir: GitHelper.git_root_dir,
        include_deleted_files: true,
      )
    changed_filenames = changed_files.all_changed_files

    log("Changed files:\n    #{changed_filenames.join("\n    ")}")
    log("")

    log "Ignoring keywords: #{[@options[:exclude_words]].flatten.join(", ")}"
    keywords = extract_keywords(changed_filenames)
    log "Keywords derived from changed files:\n    #{keywords.join("\n    ")}\n\n"

    specs = get_specs(keywords)

    if specs.any?
      log "Spec files:\n    #{specs.join("\n    ")}\n"
    else
      log "No spec files found.\n"
    end

    { specs: }.compact
  rescue GpushError => e
    ExitHelper.exit_with_error(e)
  end

  def format_specs_for_output(specs)
    specs.join(@options[:output_separator])
  end

  private

  def extract_keywords(filenames)
    partial_filenames =
      filenames.map { |filepath| File.basename(filepath, ".*") }
    keywords =
      partial_filenames.flat_map { |filename| filename.split(/[_\-\.]/) } # Split by underscore, hyphen, or period
    keywords.map!(&:downcase)
    keywords.reject! do |word|
      word.length < @options[:min_keyword_length] ||
        @options[:exclude_words].include?(word)
    end
    keywords.uniq
  end

  def get_specs(keywords)
    if @options[:include_pattern].nil?
      raise GpushError,
            "include_pattern is required. Specify in config file or with --include-pattern cli option"
    end

    log("Root dir: #{GitHelper.git_root_dir}")
    log("Spec include pattern: #{@options[:include_pattern]}")
    log "Always include pattern: #{@options[:always_include]}"
    log("")

    if @options[:always_include]
      always_include_files =
        Dir.glob File.join GitHelper.git_root_dir, @options[:always_include]
    end

    files_to_match =
      Dir.glob File.join GitHelper.git_root_dir, @options[:include_pattern]
    matching_files =
      files_to_match.each_with_object([]) do |path, specs|
        filename = File.basename(path, ".*").downcase # Returns "example_spec"
        filename_keywords = filename.split(/[_\-\.]/) # Returns ["example", "spec"]
        specs << path if filename_keywords.intersect? keywords
      end

    if always_include_files
      log("Always include files: #{always_include_files.join('     \n')}\n\n")
    end
    log("Files matching keywords: #{matching_files.join("     \n\n")}")
    matching_files | (always_include_files || [])
  end

  def log(message)
    puts message if @options[:verbose]
  end

  def self.option_definitions
    proc do |opts, options|
      opts.on(
        "-r",
        "--root-dir DIRECTORY",
        "Root directory of the project",
      ) { |dir| options[:root_dir] = dir }

      opts.on(
        "-i",
        "--include-pattern PATTERN",
        "Glob pattern to include spec files (e.g., '*spec.rb')",
      ) { |pattern| options[:include_pattern] = pattern }

      opts.on(
        "-a",
        "--always-include PATTERN",
        "Glob pattern to always include spec files",
      ) { |pattern| options[:always_include] = pattern }

      opts.on(
        "-e",
        "--exclude-words WORDS",
        "Comma-separated list of words to exclude from keywords",
      ) do |words|
        options[:exclude_words] = words.split(",").map(&:strip).map(&:downcase)
      end

      opts.on(
        "-l",
        "--min-length LENGTH",
        Integer,
        "Minimum length for keywords",
      ) { |length| options[:min_keyword_length] = length }

      opts.on(
        "-s",
        "--output-separator SEPARATOR",
        "String used to separate output filenames (default is a space)",
      ) { |separator| options[:output_separator] = separator }

      opts.on("-v", "--verbose", "Enable verbose output") do
        options[:verbose] = true
      end
    end
  end

  def self.required_options = %i[]
end

# Command-line execution
if __FILE__ == $PROGRAM_NAME
  config_prefix = "get_specs"
  options =
    GpushOptionsParser.parse(
      ARGV,
      config_prefix:,
      option_definitions: GpushGetSpecs.option_definitions,
      required_options: GpushGetSpecs.required_options,
    )

  finder = GpushGetSpecs.new(options)
  result = finder.find_matching_specs

  if result[:specs]
    output = finder.format_specs_for_output(result[:specs])
    puts output unless output.empty?
    ExitHelper.exit output.empty? ? 1 : 0
  end
end
