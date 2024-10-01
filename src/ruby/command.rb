#!/usr/bin/env ruby
require "pty"
require "io/console"
require "open3"
require_relative "gpush_error" # Import the custom error handling

class Command
  attr_reader :name, :shell, :output, :verbose, :status, :prefix_output, :pid

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

  def set_status(new_status)
    unless STATUS.include?(new_status)
      raise GpushError, "Invalid status: #{new_status}"
    end
    @status = new_status
  end

  COLORS = {
    green: "\e[32m",
    red: "\e[31m",
    white: "\e[37m",
    blue: "\e[34m",
    yellow: "\e[33m",
    magenta: "\e[35m",
    cyan: "\e[36m",
    black: "\e[30m",
    bold: "\e[1m",
    reset: "\e[0m",
  }.freeze

  SPINNER = ["|", "/", "-", '\\'].freeze

  def initialize(command_dict, verbose: false, prefix_output: true)
    if command_dict["env"]
      raise GpushError, ENV_ERROR_MESSAGE unless command_dict["env"].is_a?(Hash)
      env_prefix = command_dict["env"]&.map { |k, v| "#{k}=#{v}" }&.join(" ")
    end
    @verbose = verbose
    @output = []
    @prefix_output = prefix_output
    @name = command_dict["name"] || command_dict["shell"]
    raise GpushError, 'must have a "shell" field.' unless command_dict["shell"]
    @shell = [env_prefix, command_dict["shell"]].compact.join(" ")
    @run_if =
      command_dict["if"] && [env_prefix, command_dict["if"]].compact.join(" ")

    set_status "not started"
  end

  def with_prefix(line, prefix: name)
    "#{COLORS[:reset]}#{COLORS[:yellow]}#{prefix}:#{COLORS[:reset]} #{line}"
  end

  def run
    exit_status = nil
    set_status "working"

    # Check if the command should be run based on the 'if' condition
    if @run_if
      puts "running #{name} 'if' command: `#{@run_if}`" if verbose
      stdout, stderr, status = Open3.capture3(@run_if)
      if verbose
        { output: stdout, ERROR: stderr }.each do |label, lines|
          lines.each_line do |line|
            puts with_prefix(line, prefix: "#{name} 'if' #{label}")
          end
        end
      end
      unless status.success?
        puts "#{name} skipped because 'if' condition failed" if verbose
        set_status "skipped"
        return
      end
    end

    begin
      # Use PTY for real-time command output, capturing both stdout and stderr
      PTY.spawn(shell) do |thread_stdout, _stdin, pid|
        @pid = pid

        thread_stdout.each do |line|
          verbose ? puts(with_prefix(line)) : @output << line
        end

        # Wait for the child process to exit and capture its status
        _, exit_status = Process.wait2(pid)
      end

      # Determine the final status of the command
      if exit_status.signaled?
        set_status "interrupted"
      elsif exit_status.success?
        set_status "success"
      else
        set_status interrupting? ? "interrupted" : "fail"
      end
    rescue PTY::ChildExited => e
      puts "\n\nRESCUED Exception: #{e.message} - Command '#{name}' exited unexpectedly"
      set_status "fail"
    ensure
      print_output if fail? && !verbose # Print output if command failed and not in verbose mode
    end
  end

  def print_output
    puts "\n\n"
    extra_message =
      case status
      when "interrupted"
        " interrupted test"
      when "fail"
        " failed test"
      else
        ""
      end
    message = "Output for" + extra_message + ": #{name}"
    puts "#{COLORS[:bold]}========== #{message} ==========#{COLORS[:reset]}"
    puts output
    puts "\n\n"
  end

  def final_summary
    "#{COLORS[:reset]}#{name}: #{color}#{status.upcase}#{COLORS[:reset]}"
  end

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

  # Class method to run commands in parallel and show summary
  def self.run_in_parallel(command_defs, verbose: false)
    all_commands = command_defs.map { |cmd| new(cmd, verbose:) }

    threads = run_commands_in_threads(all_commands, verbose)

    handle_interruptions(all_commands)

    spinner_thread = start_spinner(all_commands, threads, verbose)

    threads.each(&:join)
    spinner_thread.kill

    finalize_output(all_commands, verbose)
    print_overall_summary(all_commands)
  end

  def self.run_commands_in_threads(all_commands, verbose)
    all_commands.map do |command|
      Thread.new do
        command.run
      rescue GpushError
        command.set_status "fail"
        command.print_output unless verbose
      end
    end
  end

  def self.handle_interruptions(all_commands)
    processing_interruption = false
    default_int_handler =
      Signal.trap("INT") do
        process_interrupt(
          all_commands,
          processing_interruption,
          default_int_handler,
        )
        processing_interruption = true
      end
  end

  def self.process_interrupt(
    all_commands,
    processing_interruption,
    default_int_handler
  )
    puts "\nCtrl-C detected, attempting to stop gracefully. Press Ctrl-C again to force quit."
    if processing_interruption
      execute_default_handler(default_int_handler)
    else
      interrupt_commands(all_commands)
    end
  end

  def self.execute_default_handler(default_int_handler)
    if default_int_handler.respond_to?(:call)
      default_int_handler.call
    elsif default_int_handler == "DEFAULT"
      Signal.trap("INT", "DEFAULT")
      Process.kill("INT", Process.pid)
    elsif default_int_handler == "IGNORE"
      puts "Signal was previously ignored"
    end
  end

  def self.interrupt_commands(all_commands)
    all_commands.each do |command|
      next unless command.working? || command.not_started?
      time_now = Time.now
      sleep 0.1 while !command.pid && Time.now - time_now < 2 # Wait for the command to start
      next unless command.working? || command.not_started?
      if command.pid
        Process.kill("INT", -command.pid)
        command.set_status "interrupting"
      else
        raise GpushError,
              "Command '#{command.name}' does not have a PID to interrupt"
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

  def self.finalize_output(all_commands, verbose)
    print_single_line_spinner(all_commands) unless verbose
    puts ""
    all_commands.each do |command|
      next if command.skipped? || command.success? || verbose || command.fail?
      command.print_output
    end
  end

  def self.print_overall_summary(all_commands)
    puts "\n#{COLORS[:bold]}Summary#{COLORS[:reset]}"
    all_commands.each { |cmd| puts cmd.final_summary }

    if all_commands.any?(&:interrupted?)
      puts "\n#{COLORS[:cyan]}《 Interruption detected 》#{COLORS[:reset]}"
      return false
    elsif all_commands.any?(&:fail?)
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
    "#{command[0...max_length - 4]}... " # Truncate and add ellipsis
  end

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
    print "\r#{" " * terminal_width}" # Clear the line
    print "\r#{line}"
    $stdout.flush # Ensure real-time display of the spinner
  end

  def self.over_width?(command_names)
    command_names.map(&:size).sum > terminal_width
  end
end
