# frozen_string_literal: true

require_relative "exit_helper"
require_relative "gpush_changed_files"

module GpushDiffBranch
  def self.go(args:, options:)
    if args.any?
      puts "Unexpected argument(s): #{args.join(", ")}"
      puts "Usage: gpush diff-branch [--config-file=FILE] [--verbose]"
      ExitHelper.exit(1)
    end

    subsection = options[:gpush_changed_files]
    cf_opts =
      (subsection.is_a?(Hash) ? subsection : {}).transform_keys(&:to_sym)
    cf_opts[:verbose] = true if options[:verbose]

    puts GpushChangedFiles.new(cf_opts).diff_base_ref
    ExitHelper.exit(0)
  end

  def self.option_definitions
    lambda do |opts, parsing_options|
      opts.banner = <<~BANNER
        gpush diff-branch: print the remote ref used for changed-file diffs.

        Usage:
          gpush diff-branch [options]

        Prints one line, e.g. origin/main (the ref passed to git diff by gpush_changed_files).
        If gpushrc defines gpush_changed_files: (fallback branches, etc.), those settings apply.

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
