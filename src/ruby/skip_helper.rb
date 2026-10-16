# frozen_string_literal: true

require_relative "gpush_error"

# Resolves --skip names against the commands in the config, before anything runs.
module SkipHelper
  SECTIONS = %w[
    pre_run
    parallel_run
    post_run
    post_run_success
    post_run_failure
    post_push_success
    post_push_failure
  ].freeze

  class << self
    def skip?(name, skip)
      skip.any? { |skip_name| skip_name.casecmp?(name) }
    end

    # Returns the matched commands' names as the config spells them
    def resolve(skip, options)
      return [] if skip.nil? || skip.empty?

      commands =
        SECTIONS.flat_map do |section|
          (options[section.to_sym] || []).map { |cmd| [section, cmd] }
        end

      skip.map do |skip_name|
        matches = commands.select { |_, cmd| skip?(name_of(cmd), [skip_name]) }
        case matches.size
        when 0
          raise GpushError, unknown_message(skip_name, commands)
        when 1
          name_of(matches.first[1])
        else
          raise GpushError, ambiguous_message(skip_name, matches)
        end
      end
    end

    def summary(skipped_names)
      count = skipped_names.size
      "#{count} #{count == 1 ? "check" : "checks"} skipped: #{skipped_names.join(", ")}"
    end

    private

    def name_of(cmd) = cmd["name"] || cmd["shell"]

    def unknown_message(skip_name, commands)
      names = commands.map { |_, cmd| name_of(cmd) }.uniq
      "--skip: no command named '#{skip_name}'. Commands are: #{names.join(", ")}"
    end

    def ambiguous_message(skip_name, matches)
      lines =
        matches.map do |section, cmd|
          "  #{section}: #{name_of(cmd)} (`#{cmd["shell"]}`)"
        end
      "--skip: '#{skip_name}' matches more than one command:\n#{lines.join("\n")}"
    end
  end
end
