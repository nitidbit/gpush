# frozen_string_literal: true

require "json"
require "open3"
require_relative "gpush_error"

# Preflight checks for the `claude` CLI that gpush review subcommands shell out to.
# Both run before any review work, so a missing, outdated or logged-out CLI
# fails immediately with an explanation rather than part-way through a run.
module GpushClaudeCli
  class << self
    # The caller owns the policy: it knows which CLI features it depends on,
    # so it passes the floor rather than this module hard-coding one.
    def check_version!(minimum)
      stdout = capture("--version")

      # e.g. "2.1.223 (Claude Code)"
      found = stdout[/\d+(?:\.\d+)+/]
      unless found
        raise GpushError,
              "Could not read a version from `claude --version`: " \
                "#{stdout.strip.inspect}"
      end

      return if Gem::Version.new(found) >= Gem::Version.new(minimum)

      raise GpushError,
            "claude CLI #{found} is too old for gpush Claude reviews, which " \
              "need #{minimum} or newer. Update the CLI and try again."
    end

    def check_auth!
      stdout = capture("auth", "status")

      status =
        begin
          JSON.parse(stdout)
        rescue JSON::ParserError
          raise GpushError,
                "Unexpected output from `claude auth status` (expected JSON):\n#{stdout.strip}"
        end
      return if status["loggedIn"]

      raise GpushError,
            "Not logged in to Claude. Run `claude auth login` to authenticate."
    end

    private

    # Run `claude <args>` and return its stdout, raising a GpushError that
    # names the command when the CLI is missing or exits non-zero.
    def capture(*args)
      stdout, stderr, process_status =
        begin
          Open3.capture3("claude", *args)
        rescue Errno::ENOENT
          raise GpushError,
                "`claude` CLI not found on PATH. Install it or skip this check."
        end
      return stdout if process_status.success?

      detail = stderr.strip.empty? ? stdout.strip : stderr.strip
      raise GpushError,
            "`claude #{args.join(" ")}` failed " \
              "(exit #{process_status.exitstatus})." \
              "#{"\n#{detail}" unless detail.empty?}"
    end
  end
end
