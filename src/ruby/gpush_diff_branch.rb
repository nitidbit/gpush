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
