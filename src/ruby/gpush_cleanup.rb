# frozen_string_literal: true

# The cleanup: section, which runs however gpush exits: normally, through
# ExitHelper.exit, on Ctrl-C, or on an error. It does not run on SIGKILL.
module GpushCleanup
  class << self
    def validate(commands)
      return if commands.nil?
      unless commands.is_a?(Array) && commands.all?(Hash)
        raise GpushError, "cleanup must be a list of commands"
      end

      commands.each do |cmd|
        next if cmd["shell"]

        raise GpushError,
              "cleanup command #{cmd["name"].to_s.inspect} must have a \"shell\" field"
      end
    end

    # at_exit hooks run in reverse order of registration, so register this
    # after the worktree's removal hook for cleanup to run first.
    def register(commands, options)
      return if commands.empty?

      cleanup_dir = Dir.pwd
      at_exit { run(commands, options, cleanup_dir) }
    end

    private

    # A Ctrl-C before the patient controller is installed would raise
    # Interrupt and cut cleanup off, so it is held until cleanup is done
    def run(commands, options, cleanup_dir)
      Thread.handle_interrupt(Interrupt => :never) do
        InterruptController.install(patient: true)
        Dir.chdir(cleanup_dir)
        puts "\nRunning cleanup..."
        commands.each do |cmd_dict|
          InterruptController.current.section { run_one(cmd_dict, options) }
        end
      rescue StandardError => e
        puts "cleanup failed: #{e.message}"
      ensure
        InterruptController.uninstall
      end
    end

    # Reports a failure and carries on, so every cleanup command gets its turn
    def run_one(cmd_dict, options)
      # Cleanup is never skipped, and draws no spinner to clear
      settings =
        Command.run_settings(options, cmd_dict).merge(skip: [], spinner: false)
      command = Command.new(cmd_dict, **settings)
      command.run
      return if command.success? || command.skipped?

      puts "cleanup command #{command.outcome} - #{command.name}"
    rescue StandardError => e
      puts "cleanup command failed - #{Command.name_of(cmd_dict)}: #{e.message}"
    end
  end
end
