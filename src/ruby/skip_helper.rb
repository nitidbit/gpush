# frozen_string_literal: true

require_relative "config_helper"
require_relative "gpush_error"

# Resolves --skip names against the commands in the config, before anything runs.
module SkipHelper
  SECTIONS = ConfigHelper::COMMAND_SECTIONS

  # What a section needs in order to run. Two sections whose needs conflict
  # never both run, so a name may appear in both.
  NEEDS = {
    "post_run_success" => %i[checks_passed],
    "post_run_failure" => %i[checks_failed],
    "post_push_success" => %i[checks_passed push_succeeded],
    "post_push_failure" => %i[checks_passed push_failed],
  }.freeze
  CONFLICTING_NEEDS = [
    %i[checks_passed checks_failed],
    %i[push_succeeded push_failed],
  ].freeze

  class << self
    def skip?(name, skip)
      skip.any? { |skip_name| skip_name.casecmp?(name.to_s) }
    end

    # Fails fast, before git or any command runs, on a name no command has,
    # or one that matches more than one command that could both run
    def validate_names(options)
      return if options[:skip].nil? || options[:skip].empty?

      commands = SECTIONS.flat_map { |section| commands_in(options, section) }
      options[:skip].each do |skip_name|
        next if commands.any? { |cmd| skip?(Command.name_of(cmd), [skip_name]) }

        if commands_in(options, "cleanup").any? { |cmd|
             skip?(Command.name_of(cmd), [skip_name])
           }
          raise GpushError,
                "--skip: '#{skip_name}' is a cleanup command, which can't be skipped"
        end
        raise GpushError, unknown_message(skip_name, commands)
      end
      reject_ambiguous_names(options)
    end

    # The commands actually skipped this run, as the config spells them
    def skipped_names = skips_lock.synchronize { skipped.dup }

    def record_skip(name)
      skips_lock.synchronize { skipped << name unless skipped.include?(name) }
    end

    def reset_skips = skips_lock.synchronize { skipped.clear }

    # " with 2 checks skipped: a, b", or "" when nothing was skipped
    def summary
      names = skipped_names
      return "" if names.empty?

      count = names.size
      " with #{count} #{count == 1 ? "check" : "checks"} skipped: #{names.join(", ")}"
    end

    private

    def skipped = @skipped ||= []

    def skips_lock = @skips_lock ||= Mutex.new

    # Only commands that can run in this mode count: worktree or not, and no
    # post_push_* on a dry run
    def reject_ambiguous_names(options)
      sections = SECTIONS
      sections -= %w[post_push_success post_push_failure] if options[:dry_run]
      commands =
        sections.flat_map do |section|
          runnable(options, section).map { |cmd| [section, cmd] }
        end

      options[:skip].each do |skip_name|
        matches =
          commands.select { |_, cmd| skip?(Command.name_of(cmd), [skip_name]) }
        if matches.empty?
          puts "--skip: '#{skip_name}' #{why_nothing_runs(options, skip_name)}"
        elsif can_both_run?(matches)
          raise GpushError, ambiguous_message(skip_name, matches)
        end
      end
    end

    # The name has commands (validate_names checked), but none run this time
    def why_nothing_runs(options, skip_name)
      matches =
        SECTIONS.flat_map do |section|
          commands_in(options, section)
            .select { |cmd| skip?(Command.name_of(cmd), [skip_name]) }
            .map { |cmd| [section, cmd] }
        end
      reasons =
        matches.map do |section, cmd|
          if options[:dry_run] && section.start_with?("post_push")
            "is only in #{section}, which doesn't run with --dry-run"
          elsif cmd["only_worktree"]
            "is only on only_worktree commands, and this run isn't in a worktree"
          else
            "is only on only_no_worktree commands, and this run is in a worktree"
          end
        end
      reasons.uniq.join("; ")
    end

    def can_both_run?(matches)
      matches
        .combination(2)
        .any? do |(section, _), (other_section, _)|
          !never_both_run?(section, other_section)
        end
    end

    def never_both_run?(section, other_section)
      needs = NEEDS.fetch(section, []) + NEEDS.fetch(other_section, [])
      CONFLICTING_NEEDS.any? { |pair| (pair - needs).empty? }
    end

    def runnable(options, section)
      Command.runnable(
        commands_in(options, section),
        in_worktree: !!options[:worktree],
      )
    end

    # Malformed entries are left for the runner to report
    def commands_in(options, section)
      commands = options[section.to_sym]
      commands.is_a?(Array) ? commands.grep(Hash) : []
    end

    def unknown_message(skip_name, commands)
      names = commands.filter_map { |cmd| Command.name_of(cmd) }.uniq
      "--skip: no command named '#{skip_name}'. Commands are: #{names.join(", ")}"
    end

    def ambiguous_message(skip_name, matches)
      lines =
        matches.map do |section, cmd|
          "  #{section}: #{Command.name_of(cmd)} (`#{cmd["shell"]}`)"
        end
      "--skip: '#{skip_name}' matches more than one command:\n#{lines.join("\n")}"
    end
  end
end
