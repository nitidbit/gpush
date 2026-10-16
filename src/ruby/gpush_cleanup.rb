# frozen_string_literal: true

# The cleanup: section, which runs however gpush exits: normally, through
# ExitHelper.exit, or on Ctrl-C. It does not run on SIGKILL or a crash.
module GpushCleanup
  class << self
    # at_exit hooks run in reverse order of registration, so register this
    # after the worktree's removal hook for cleanup to run first.
    def register(commands, options)
      return if commands.empty?

      cleanup_dir = Dir.pwd
      at_exit do
        Dir.chdir(cleanup_dir)
        run(commands, options)
      end
    end

    private

    def run(commands, options)
      previous_int_handler =
        Signal.trap("INT") { puts "\nCtrl-C ignored until cleanup finishes." }
      Gpush.simple_run_commands_with_output(
        commands,
        title: "cleanup",
        options:,
        halt_on_failure: false,
      )
    rescue StandardError => e
      puts "cleanup failed: #{e.message}"
    ensure
      Signal.trap("INT", previous_int_handler || "DEFAULT")
    end
  end
end
