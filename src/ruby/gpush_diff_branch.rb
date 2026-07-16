# frozen_string_literal: true

require_relative "exit_helper"
require_relative "gpush_changed_files"

module GpushDiffBranch
  def self.description
    "Print the remote ref (e.g. origin/main) that changed-files uses for git diff; honors optional gpush_changed_files: settings in gpushrc."
  end

  def self.go(args:, options:)
    if args.any?
      puts "Unexpected argument(s): #{args.join(", ")}"
      puts "Usage: gpush diff-branch [--config-file=FILE] [--verbose]"
      ExitHelper.exit(1)
    end

    puts base_ref(options)
    ExitHelper.exit(0)
  end

  # The remote ref reviews and changed-file diffs are based on, e.g. origin/main.
  def self.base_ref(options)
    GpushChangedFiles.from_options(options).diff_base_ref
  end

  def self.option_definitions
    lambda do |opts, parsing_options|
      opts.banner = <<~BANNER
        gpush diff-branch: #{description}

        Usage:
          gpush diff-branch [options]

        Options:
      BANNER
      opts.on("--config-file=FILE", "Specify a custom config file") do |file|
        parsing_options[:config_file] = file
      end
      opts.on("-v", "--verbose", "Show which branch is used for the diff") do
        parsing_options[:verbose] = true
      end
    end
  end
end
