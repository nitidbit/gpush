#!/usr/bin/env ruby
require "pty"
require "io/console"
require "monitor"
require "open3"
require_relative "colors"
require_relative "gpush_error"
require_relative "gpush_options_parser"
require_relative "interrupt_controller"
require_relative "skip_helper"

class Command
  attr_reader :name,
              :shell,
              :output,
              :verbose,
              :status,
              :prefix_output,
              :spinner_enabled,
              :pid,
              :start_time,
              :end_time

  STATUS = %w[
    not\ started
    working
    success
    fail
    skipped
    interrupted
    interrupting
  ].freeze

  ENV_ERROR_MESSAGE = "The 'env' field must be a hash of key-value pairs".freeze

  KNOWN_COMMAND_KEYS = %w[
    shell
    name
    env
    if
    verbose
    only_worktree
    only_no_worktree
  ].freeze

  def set_status(new_status)
    unless STATUS.include?(new_status)
      raise GpushError, "Invalid status: #{new_status}"
    end
    @status_lock.synchronize { @status = new_status }
  end

  SPINNER = ["|", "/", "-", '\\'].freeze

  def initialize(
    command_dict,
    verbose: false,
    prefix_output: true,
    spinner: true,
    skip: []
  )
    # The watcher thread marks a command interrupting while its own thread may
    # be setting the final status
    @status_lock = Monitor.new
    # Kept, so a command left running after a force quit can't start under
    # whatever controller (or none) comes next
    @controller = InterruptController.current
    warn_unknown_command_keys(command_dict)

    if command_dict["env"]
      raise GpushError, ENV_ERROR_MESSAGE unless command_dict["env"].is_a?(Hash)
      env_prefix = command_dict["env"]&.map { |k, v| "#{k}=#{v}" }&.join(" ")
    end
    @verbose = verbose
    @output = []
    @prefix_output = prefix_output
    @spinner_enabled = spinner
    @name = self.class.name_of(command_dict)
    raise GpushError, 'must have a "shell" field.' unless command_dict["shell"]
    @skipped_by_flag = SkipHelper.skip?(@name, skip)
    @shell = [env_prefix, command_dict["shell"]].compact.join(" ")
    @run_if =
      command_dict["if"] && [env_prefix, command_dict["if"]].compact.join(" ")

    set_status "not started"

    # Set the working directory correctly before running the command
    set_working_directory
  end

  def with_prefix(line, prefix: name)
    "#{COLORS[:reset]}#{COLORS[:yellow]}#{prefix}:#{COLORS[:reset]} #{line}"
  end

  # Set the working directory based on the config file or git root
  def set_working_directory
    working_dir = Dir.pwd
    acceptable_directories = [
      ConfigHelper.config_file_dir,
      GitHelper.git_root_dir,
    ].compact

    until acceptable_directories.include?(working_dir) || working_dir == "/" # rubocop:disable Style/WhileUntilModifier
      working_dir = File.expand_path("..", working_dir)
    end

    Dir.chdir(working_dir) unless ["/", Dir.pwd].include?(working_dir)
  end

  def run
    @start_time = Time.now # Start time for duration tracking
    set_status "working"

    case precondition
    when :skipped
      set_status "skipped"
      return
    when :interrupted
      set_status "interrupted"
      return false
    end

    started = false
    begin
      # A force quit's Interrupt waits while the process is spawned and
      # registered, and while it is unregistered, so neither step is skipped
      Thread.handle_interrupt(Interrupt => :never) { started = spawn }
      unless started
        set_status "interrupted" unless fail?
        return false
      end

      wait_for_exit
    ensure
      if started
        Thread.handle_interrupt(Interrupt => :never) do
          [@reader, @writer].each { |io| io&.close unless io&.closed? }
          @controller.finished(self)
        end
      end
    end
    success?
  ensure
    @end_time = Time.now # End time for duration tracking
    print_nonverbose_output if show_output_after_run?
  end

  # Without verbose, output is held back unless the command failed or was
  # interrupted part way (one stopped before it started has none)
  def show_output_after_run?
    !verbose && (fail? || (interrupted? && output.any?))
  end

  def wait_for_exit
    read_output
    _, exit_status = Process.wait2(pid)
    if exit_status.success?
      set_status "success"
    elsif interrupting?
      # Only a command gpush sent Ctrl-C counts as interrupted; one killed
      # by anything else (a crash, the OOM killer) failed
      set_status "interrupted"
    else
      set_status "fail"
    end
  end

  def mark_interrupting
    @status_lock.synchronize { set_status "interrupting" if working? }
  end

  # Uses PTY for real-time output, capturing both stdout and stderr. Returns
  # false when the section was interrupted first or the shell can't start.
  def spawn
    started =
      @controller.start(self) do
        @reader, @writer, @pid = PTY.spawn(shell)
        @pid
      end
    puts with_prefix("running shell command `#{shell}`") if started && verbose
    started
  rescue SystemCallError => e
    verbose ? puts(with_prefix(e.message)) : @output << e.message
    set_status "fail"
    false
  end

  def read_output
    @reader.each do |line|
      verbose ? puts(prefix_output ? with_prefix(line) : line) : @output << line
    end
  rescue Errno::EIO
    # Linux reports the end of a PTY's output as EIO rather than EOF
  end

  def outcome = interrupted? ? "interrupted" : "failed"

  # :run, :skipped (by --skip or a failing `if`), or :interrupted
  def precondition
    if @skipped_by_flag
      puts "#{name} skipped by --skip" if verbose
      SkipHelper.record_skip(name)
      return :skipped
    end
    return :run unless @run_if

    puts with_prefix("running 'if' command `#{@run_if}`") if verbose
    output, errors, status = run_if_check
    return :interrupted unless status # its section was interrupted first

    print_if_output(output, errors) if verbose
    # A check cut short by Ctrl-C says nothing about whether to skip
    return :interrupted if status.signaled? || @controller.interrupted?
    return :run if status.success?

    puts "#{name} skipped because 'if' condition failed" if verbose
    :skipped
  rescue SystemCallError => e
    return :interrupted if @controller.interrupted?

    # Like any failing `if`, e.g. a tool that isn't installed on this machine
    if verbose
      puts "#{name} skipped because 'if' command couldn't start: #{e.message}"
    end
    :skipped
  end

  # Outside cleanup, the check runs in gpush's own process group, so one that
  # prompts on the terminal still can, and a terminal Ctrl-C reaches it
  # directly. In cleanup, where a first Ctrl-C is only a warning, it runs in
  # its own group, registered like a command so a later press can stop it.
  def run_if_check
    return Open3.capture3(@run_if) unless @controller.patient?

    stdin = stdout = stderr = waiter = nil
    started =
      @controller.start(self) do
        stdin, stdout, stderr, waiter = Open3.popen3(@run_if, pgroup: true)
        waiter.pid
      end
    return nil, nil, nil unless started

    stdin.close
    output, errors =
      [stdout, stderr].map { |io| Thread.new { io.read } }.map(&:value)
    [output, errors, waiter.value]
  ensure
    [stdin, stdout, stderr].each { |io| io&.close unless io&.closed? }
    @controller.finished(self) if started
  end

  def print_if_output(output, errors)
    { output:, ERROR: errors }.each do |label, lines|
      lines.each_line do |line|
        puts with_prefix(line, prefix: "#{name} 'if' #{label}")
      end
    end
  end

  def print_nonverbose_output
    # Clear spinner, it will be reprinted below this output
    self.class.clear_single_line_spinner if spinner_enabled
    puts "\n\n"
    extra_message =
      case status
      when "interrupted"
        " interrupted command"
      when "fail"
        " failed command"
      else
        ""
      end
    message = "Output for#{extra_message}: #{name}"
    puts "#{COLORS[:bold]}========== #{message} ==========#{COLORS[:reset]}"
    puts output
    puts "\n\n"
  end

  def final_summary
    reason = " (by --skip)" if @skipped_by_flag
    "#{COLORS[:reset]}#{name}: #{color}#{status.upcase}#{COLORS[:reset]}#{reason} #{duration_text}"
  end

  def duration = end_time && start_time ? (end_time - start_time) : nil

  def duration_text
    return unless duration
    return wrap_in_color("<1s", :white) if duration < 1
    return wrap_in_color("#{duration.round(1)}s", :white) if duration < 60
    minutes = (duration / 60).to_i
    wrap_in_color "#{minutes}m #{(duration - (minutes * 60)).round}s", :white
  end

  def wrap_in_color(text, color) = "#{COLORS[color]}#{text}#{COLORS[:reset]}"

  def spinner
    return "✓" if success?
    return "✗" if fail?
    return "⏭" if skipped?
    return "⏸" if interrupted?
    return "⏳" if interrupting?
    return "…" if verbose
    SPINNER[output.length % SPINNER.size]
  end

  def color
    case status
    when "success"
      COLORS[:green]
    when "fail"
      COLORS[:red]
    when "skipped"
      COLORS[:yellow]
    when "interrupted", "interrupting"
      COLORS[:cyan]
    when "not started", "working"
      COLORS[:white] # Still running
    else
      raise "unexpected status: #{status}"
    end
  end

  def warn_unknown_command_keys(command_dict)
    unknown = command_dict.keys.map(&:to_s) - KNOWN_COMMAND_KEYS
    return if unknown.empty?
    command_id = self.class.name_of(command_dict) || "unknown"
    unknown.each do |key|
      puts ""
      puts "#{COLORS[:bold_red]}WARNING: Unknown config key '#{key}' in command '#{command_id}'#{COLORS[:reset]}"
      puts "#{COLORS[:yellow]}This key will be ignored. Check gpushrc.yml for typos.#{COLORS[:reset]}"
      puts ""
    end
  end

  def self.status_method_names
    STATUS.map { |st| :"#{st.gsub(" ", "_")}?" }
  end

  def method_missing(method_name, *args, &)
    return super unless self.class.status_method_names.include?(method_name)
    @status == method_name.to_s.chomp("?").gsub("_", " ")
  end

  def respond_to_missing?(method_name, include_private = false)
    self.class.status_method_names.include?(method_name) || super
  end

  def self.name_of(command_dict) = command_dict["name"] || command_dict["shell"]

  def self.runnable(commands, in_worktree:)
    (commands || []).reject do |cmd|
      (cmd["only_worktree"] && !in_worktree) ||
        (cmd["only_no_worktree"] && in_worktree)
    end
  end

  # The gpush options a command run depends on, with their defaults
  # With a command's own entry, its verbose setting overrides the global one
  def self.run_settings(options, command_dict = {})
    own_verbose = command_dict["verbose"]
    {
      verbose: own_verbose.nil? ? options[:verbose] : own_verbose,
      spinner: options[:spinner] != false,
      skip: options[:skip] || [],
    }
  end

  # Class method to run commands in parallel and show summary
  def self.run_in_parallel?(command_defs, options: {})
    verbose, spinner, skip =
      run_settings(options).values_at(:verbose, :spinner, :skip)
    all_commands =
      command_defs.map { |cmd| new(cmd, verbose:, spinner:, skip:) }

    announce_commands(all_commands) unless spinner

    InterruptController
      .current
      .section(spinner:) do
        threads = run_commands_in_threads(all_commands, verbose, spinner:)
        spinner_thread =
          start_spinner(all_commands, threads, verbose) if spinner
        begin
          threads.each(&:join)
        ensure
          spinner_thread&.kill
          # After a force quit, so their last output lands before cleanup's
          deadline = Time.now + InterruptController::STOP_GRACE_SECONDS
          threads.each { |thread| thread.join([deadline - Time.now, 0].max) }
        end
      end

    finalize_output(all_commands, verbose, spinner:)
    print_summary_and_return_all_succeeded?(
      all_commands,
      # A Ctrl-C that landed as the commands finished interrupted nothing,
      # but still means stop
      interrupted: InterruptController.current.interrupted?,
    )
  end

  # Without the spinner there is no live progress, so at least say what started
  def self.announce_commands(all_commands)
    return if all_commands.empty?
    puts "Running #{all_commands.size} commands: #{all_commands.map(&:name).join(", ")}"
  end

  def self.run_commands_in_threads(all_commands, verbose, spinner: true)
    all_commands.map do |command|
      Thread.new do
        command.run
      rescue StandardError => e
        # Anything that stops a check from finishing fails it, so the run
        # can't count it as passed
        command.output << e.message
        command.set_status "fail"
        command.print_nonverbose_output unless verbose
      ensure
        # Without the spinner, this is the only sign a command has finished
        puts command.final_summary unless spinner
      end
    end
  end

  def self.start_spinner(all_commands, threads, verbose)
    Thread.new do
      old_status = nil
      while threads.any?(&:alive?)
        new_status = all_commands.map(&:status) if verbose
        if old_status != new_status || !verbose
          puts "" if verbose
          print_single_line_spinner(all_commands)
          puts "\n\n" if verbose
          old_status = new_status if verbose
        end
        sleep 0.3
      end
    end
  end

  def self.finalize_output(all_commands, verbose, spinner: true)
    print_single_line_spinner(all_commands) if spinner && !verbose
    puts ""
  end

  def self.print_summary_and_return_all_succeeded?(
    all_commands,
    interrupted: false
  )
    puts "\n#{COLORS[:bold]}Summary#{COLORS[:reset]}"
    all_commands.each { |cmd| puts cmd.final_summary }

    if interrupted || all_commands.any?(&:interrupted?)
      puts "\n#{COLORS[:cyan]}《 Interruption detected 》#{COLORS[:reset]}"
      return false
    elsif all_commands.any? { |cmd| !(cmd.success? || cmd.skipped?) }
      puts "\n#{COLORS[:red]}《 Errors detected 》#{COLORS[:reset]}"
      return false
    end

    puts "\n#{COLORS[:green]}《 No errors detected 》#{COLORS[:reset]}"
    true
  end

  def self.terminal_width
    width =
      begin
        IO.console.winsize[1]
      rescue StandardError
        nil
      end
    width ||=
      begin
        `tput cols`.to_i
      rescue StandardError
        80
      end
    width > 0 ? width : 80 # Default to 80 if no valid width is found
  end

  def self.truncate_command_name(command, max_length)
    return command if command.length <= max_length
    "#{command[0...(max_length - 4)]}... " # Truncate and add ellipsis
  end

  def self.clear_single_line_spinner = print "\r#{" " * terminal_width}"

  def self.print_single_line_spinner(all_commands)
    command_names =
      all_commands.map { |command| "[#{command.spinner}]#{command.name}  " }
    command_names.map! { |name| name[0..-2] } if over_width?(command_names)
    if over_width?(command_names)
      command_names.map! { |name| "#{name.gsub(/\s/, "")} " }
    end
    if over_width?(command_names)
      # remove the [] brackets
      command_names.map! { |name| name[1] + name[3..] }
    end
    if over_width?(command_names)
      command_names.map! do |cmd|
        truncate_command_name(cmd, terminal_width / command_names.size)
      end
    end

    line =
      all_commands
        .map
        .with_index do |cmd, index|
          command_name = command_names[index]
          "#{cmd.color}#{command_name}#{COLORS[:reset]}"
        end
        .join

    # Print the single-line spinner and command status
    clear_single_line_spinner
    print "\r#{line}"
    $stdout.flush # Ensure real-time display of the spinner
  end

  def self.over_width?(command_names)
    command_names.map(&:size).sum > terminal_width
  end
end
