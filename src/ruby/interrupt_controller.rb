# frozen_string_literal: true

# Owns Ctrl-C while gpush runs its sections.
#
# - The first press in a section sends Ctrl-C to that section's running
#   commands, and no more of its commands start. Each interrupted command
#   takes as long as it needs to exit; whatever it leaves behind in its
#   process group then gets one grace period before SIGKILL.
# - A second press in that section, or a press between sections, force quits:
#   every running or interrupted process group gets Ctrl-C, then SIGKILL
#   after one grace period, and Interrupt is raised in the thread that
#   installed the controller.
# - A patient controller (for cleanup) only warns on the first press; each
#   later press stops the running command, and the run carries on.
#
# Commands run in their own process groups, so Ctrl-C from the terminal
# reaches only gpush. (`if` checks stay in gpush's group, so they can prompt
# on the terminal, and get a terminal Ctrl-C directly.) Signal handlers can't take locks, so
# the trap only queues the press and a watcher thread acts on it.
class InterruptController
  STOP_GRACE_SECONDS = 5

  # Stands in when no controller is installed (subcommands, most specs)
  module Unmanaged
    def self.start(_command) = yield && true
    def self.finished(_command) = nil
    def self.section(**) = yield
    def self.interrupted? = false
    def self.patient? = false
  end

  class << self
    def current = @current || Unmanaged

    def install(patient: false)
      uninstall
      @current = new(patient:)
      @current.install
    end

    def uninstall
      @current&.uninstall
    ensure
      @current = nil
    end
  end

  def initialize(patient: false)
    @patient = patient
    @mutex = Mutex.new
    @presses = Queue.new
    @owner = Thread.current
    @running = {} # command => process group id
    @interrupted_groups = []
    @in_section = false
    @section_interrupted = false
    @spinner = false
    @warned = false
    @stopper = nil
    @force_quitting = false
    @interrupt_raised = false
  end

  def install
    @previous_handler =
      Signal.trap("INT") do
        # Ctrl-C must never go dead: without a watcher, quit the plain way
        raise Interrupt unless @watcher&.alive?

        @presses << :ctrl_c
      end
    @watcher = Thread.new { watch }
  end

  def uninstall
    hold_while_force_quitting
  ensure
    @watcher&.kill
    # Before joining, so an Interrupt the stopper raises can't skip it
    Signal.trap("INT", @previous_handler || "DEFAULT")
    @stopper&.join
  end

  # spinner: whether a single-line spinner is drawing, to clear before
  # printing over it
  def section(spinner: false)
    hold_while_force_quitting
    @mutex.synchronize do
      @in_section = true
      @section_interrupted = false
      @interrupted_groups = []
      @spinner = spinner
    end
    completed = false
    result = yield
    completed = true
    result
  ensure
    # Left by an error or a signal other than Ctrl-C (a CI cancel's SIGTERM,
    # a closed pipe): nothing it started may run on into cleanup
    stop_abandoned unless completed
    stop_leftovers
    @mutex.synchronize do
      @in_section = false
      @spinner = false
    end
    hold_while_force_quitting
  end

  # Runs the block, which spawns a process in its own group and returns its
  # pid, unless the section was interrupted. Returns whether it ran.
  #
  # The spawn happens under the lock, so a Ctrl-C is handled either before it
  # (and refuses it) or after the process is registered (and signals it).
  def start(command)
    @mutex.synchronize do
      return false if @section_interrupted || @force_quitting

      @running[command] = yield
      true
    end
  end

  def finished(command) = @mutex.synchronize { @running.delete(command) }

  def patient? = @patient

  def interrupted?
    @mutex.synchronize { @section_interrupted || @force_quitting }
  end

  private

  def watch
    loop do
      @presses.pop
      handle_ctrl_c
    rescue StandardError => e
      puts "\nError handling Ctrl-C (#{e.message}); press Ctrl-C again to quit."
    end
  end

  # Each action gets its targets as they were when it was chosen, under the
  # same lock, so a press can't land on the next section's commands
  def handle_ctrl_c
    action, targets =
      @mutex.synchronize { @patient ? patient_action : impatient_action }
    case action
    when :force_quit, :stop_running
      # Stopping takes a while; the watcher stays free to answer presses
      @stopper = Thread.new { send(action, targets) }
    else
      send(action, targets)
    end
  end

  # Called with the lock held
  def impatient_action
    if @force_quitting
      [:already_stopping, nil]
    elsif !@in_section || @section_interrupted
      @force_quitting = true
      [:force_quit, (@running.values + @interrupted_groups).uniq]
    else
      @section_interrupted = true
      # Recorded before signalling, so the section can't close first
      @interrupted_groups.concat(@running.values)
      [:interrupt, @running.dup]
    end
  end

  # Called with the lock held
  def patient_action
    if !@warned
      @warned = true
      [:warn_patient, nil]
    elsif @stopper&.alive?
      [:already_stopping, nil]
    else
      @section_interrupted = true
      @interrupted_groups.concat(@running.values)
      [:stop_running, @running.dup]
    end
  end

  def interrupt(running)
    say "Ctrl-C detected, attempting to stop gracefully. Press Ctrl-C again to force quit."
    running.each do |command, group|
      command.mark_interrupting
      signal(group, "INT")
    end
  end

  def warn_patient(_targets)
    say "Ctrl-C ignored until cleanup finishes. Press Ctrl-C again to stop the running cleanup command."
  end

  def stop_running(running)
    say "Stopping the running cleanup command..."
    running.each_key(&:mark_interrupting)
    report_survivors(stop_groups(running.values))
  end

  def force_quit(groups)
    say "Force quitting: stopping every running command..."
    report_survivors(stop_groups(groups))
  ensure
    # Raised however the stopping went, or Ctrl-C would go dead
    @owner.raise(Interrupt)
    # Set only once raised, so the owner can't move on before it lands
    @mutex.synchronize { @interrupt_raised = true }
  end

  def already_stopping(_targets) = say("Already stopping, please wait.")

  def say(message)
    Command.clear_single_line_spinner if @mutex.synchronize { @spinner }
    puts "\n#{message}"
  end

  def stop_abandoned
    groups = @mutex.synchronize { @running.values }
    report_survivors(stop_groups(groups)) if groups.any?
  end

  # Once an interrupted section's commands have exited, whatever they left
  # in their process groups would run on into the next section or cleanup.
  def stop_leftovers
    groups = live_interrupted_groups
    report_survivors(stop_groups(groups)) if groups.any?
  end

  # Ctrl-C, then SIGKILL once one grace period is up. Returns the survivors.
  def stop_groups(groups)
    groups.each { |group| signal(group, "INT") }
    unless gone_within_grace?(groups)
      groups.each { |group| signal(group, "KILL") if group_alive?(group) }
      gone_within_grace?(groups)
    end
    groups.select { |group| group_alive?(group) }
  end

  def report_survivors(survivors)
    return if survivors.empty?

    puts "Could not stop process groups: #{survivors.join(", ")}"
  end

  # Keeps the owner from moving on while a force quit is under way; the
  # Interrupt it raises ends the wait.
  def hold_while_force_quitting
    return if Thread.current != @owner

    sleep 0.05 while interrupt_pending?
  end

  def interrupt_pending?
    @mutex.synchronize { @force_quitting && !@interrupt_raised }
  end

  # Drops groups once they are gone, so a reused group id is never signalled
  def live_interrupted_groups
    @mutex.synchronize do
      @interrupted_groups.select! { |group| group_alive?(group) }
      @interrupted_groups.dup
    end
  end

  def gone_within_grace?(groups)
    deadline = Time.now + STOP_GRACE_SECONDS
    while groups.any? { |group| group_alive?(group) }
      return false if Time.now > deadline
      sleep 0.05
    end
    true
  end

  def signal(group, signal)
    Process.kill(signal, -group)
  rescue Errno::ESRCH, Errno::EPERM
    nil
  end

  def group_alive?(group)
    Process.kill(0, -group)
    true
  rescue Errno::ESRCH, Errno::EPERM
    false
  end
end
