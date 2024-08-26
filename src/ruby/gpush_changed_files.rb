#!/usr/bin/env ruby
# frozen_string_literal: true

class GpushChangedFiles
  DEFAULT_FALLBACK_BRANCHES = %w[main master].freeze

  OPTIONS = {
    root_dir: Dir.pwd, # Default to the current directory
    fallback_branches: DEFAULT_FALLBACK_BRANCHES,
    verbose: false,
    separator: " ",
  }.freeze

  def initialize(args = {})
    @options = OPTIONS.merge(args)
    validate_options
  end

  def git_changed_files
    branch_name = `git rev-parse --abbrev-ref HEAD`.strip
    origin_branch = "origin/#{branch_name}"

    branch_exists =
      system("git ls-remote --heads origin #{branch_name} > /dev/null 2>&1")

    if branch_exists
      diff_command = "git diff --name-only #{origin_branch}"
    else
      fallback_branch =
        @options[:fallback_branches].find do |fallback|
          system("git ls-remote --heads origin #{fallback} > /dev/null 2>&1")
        end

      if fallback_branch
        diff_command = "git diff --name-only origin/#{fallback_branch}"
        log(
          "Branch not found on origin. Falling back to origin/#{fallback_branch}.",
        )
      else
        puts "Branch not found on origin and no fallback branches available."
        exit 1
      end
    end

    Dir.chdir(@options[:root_dir]) { `#{diff_command}`.split("\n") }
  end

  def format_changed_files(files = git_changed_files)
    files.join(@options[:separator])
  end

  private

  def validate_options
    return if @options[:root_dir]
    puts "Error: root_dir is required."
    exit 1
  end

  def log(message)
    puts message if @options[:verbose]
  end
end

if __FILE__ == $PROGRAM_NAME
  changed_files_finder = GpushChangedFiles.new
  changed_files = changed_files_finder.git_changed_files
  output = changed_files_finder.format_changed_files(changed_files)
  puts output if changed_files.any?
end
