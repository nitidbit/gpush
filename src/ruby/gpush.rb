#!/usr/bin/env ruby
require "optparse"
require_relative "gpush_version"
require_relative "command" # Import the external command runner
require_relative "config_helper" # Import the config helper
require_relative "exit_helper" # Import the exit helper
require_relative "git_helper" # Import Git helper methods
require_relative "gpush_error" # Import the custom error handling
require_relative "gpush_diff_branch" # Import the diff-branch subcommand
require_relative "gpush_fix" # Import the fix command
require_relative "gpush_options_parser" # Import the options parser
require_relative "gpush_run" # Import the version checker
require_relative "notifier" # Import the desktop notifier
require_relative "version_checker" # Import the version checker
require_relative "worktree_helper" # Import the worktree helper
require_relative "gpush_cli"

EXITING_MESSAGE = "\nExiting gpush.".freeze

module Gpush
  class << self
    def parse_cmd(str, verbose:)
      verbose ? str : "#{str} > /dev/null 2>&1"
    end

    def simple_run_commands_with_output(commands, title:, verbose:)
      return if commands.nil? || commands.empty?
      some_verbose = verbose || commands.any? { |cmd| cmd["verbose"] }

      puts "\n"
      print "Running #{title}..."
      puts "\n" if some_verbose

      commands.each do |cmd_dict|
        # Use command's verbose setting if specified, otherwise use global verbose setting
        command_verbose =
          cmd_dict["verbose"].nil? ? verbose : cmd_dict["verbose"]
        command = Command.new(cmd_dict, verbose: command_verbose)
        command.run
        next if command.success?

        message = "#{title} command failed - #{command.name}"
        message += " (`#{command.shell}`)" if command.shell != command.name
        puts "#{message}\nHalting further execution and exiting gpush"
        exit 1 # Halt execution if a command fails
      end

      some_verbose ? puts("#{title} DONE") : print("DONE\n")
      puts "\n"
    end

    def check_git_state_return_nil_for_exit(dry_run)
      will_set_up_remote_branch = false

      if GitHelper.not_a_git_repository?
        puts "Not inside a Git repository. Exiting."
        return nil
      elsif !dry_run && GitHelper.detached_head?
        puts "Cannot push from a detached HEAD"
        if GitHelper.ask_yes_no("Run tests anyway?", default: true)
          dry_run = true
        else
          puts EXITING_MESSAGE
          return nil
        end
      elsif !dry_run && !GitHelper.remote_branch_name
        will_set_up_remote_branch =
          GitHelper.user_wants_to_set_up_remote_branch?
      elsif !dry_run && GitHelper.behind_remote_branch?
        puts "Cannot push to remote branch"
        output = `git status | grep 'branch'`
        output = `git status | grep 'HEAD'` if output.empty?
        output = `git status` if output.empty?
        puts output
        if GitHelper.ask_yes_no("Run tests anyway?", default: true)
          dry_run = true
        else
          puts EXITING_MESSAGE
          return nil
        end
      elsif !dry_run
        unless GitHelper.up_to_date_or_ahead_of_remote_branch?
          puts "Local branch is not up to date with the remote branch. Exiting."
          return nil
        end

        if GitHelper.at_same_commit_as_remote_branch?
          question =
            "Your branch is up to date with origin (nothing to push). Run tests anyway?"
          if GitHelper.ask_yes_no(question, default: true)
            dry_run = true
          else
            puts EXITING_MESSAGE
            return nil
          end
        end
      end

      [dry_run, will_set_up_remote_branch]
    end

    def go(options)
      git_state_result = check_git_state_return_nil_for_exit(options[:dry_run])
      return unless git_state_result

      dry_run, will_set_up_remote_branch = git_state_result

      puts "Starting dry run" if dry_run

      worktree_result =
        if will_set_up_remote_branch && options[:worktree]
          puts "Cannot create a new remote branch from a worktree (git push -u requires a real branch)."
          unless GitHelper.ask_yes_no("Run without worktree?", default: true)
            puts EXITING_MESSAGE
            return
          end
          false
        else
          !!options[:worktree]
        end

      original_dir = Dir.pwd
      original_branch = GitHelper.local_branch_name
      worktree_path = nil

      if worktree_result
        git_root = GitHelper.git_root_dir
        ENV["GPUSH_BRANCH"] = original_branch
        worktree_path =
          WorktreeHelper.create(
            git_root: git_root,
            symlink_dirs: options[:worktree_symlink_dirs] || [],
          )
        at_exit { WorktreeHelper.remove(worktree_path) }
        puts "Running in worktree: #{worktree_path}"

        if options[:worktree_copy_gitignored]
          puts "Copying gitignored files into worktree..."
          WorktreeHelper.copy_gitignored(
            git_root: git_root,
            worktree_path: worktree_path,
            globs: options[:worktree_copy_gitignored],
          )
        end

        Dir.chdir(worktree_path)
      end

      verbose = options[:verbose]

      simple_run_commands_with_output(
        options[worktree_path ? :worktree_pre_run : :no_worktree_pre_run],
        title: worktree_path ? "worktree-pre-run" : "no-worktree-pre-run",
        verbose:,
      )

      simple_run_commands_with_output(
        options[:pre_run],
        title: "pre-run",
        verbose:,
      )

      success = Command.run_in_parallel?(options[:parallel_run] || [], verbose:)

      simple_run_commands_with_output(
        options[:post_run],
        title: "post-run",
        verbose:,
      )

      simple_run_commands_with_output(
        options[worktree_path ? :worktree_post_run : :no_worktree_post_run],
        title: worktree_path ? "worktree-post-run" : "no-worktree-post-run",
        verbose:,
      )

      unless success
        simple_run_commands_with_output(
          options[:post_run_failure],
          title: "post-run failure",
          verbose:,
        )
        Notifier.notify(success: false)
        puts "Exiting gpush."
        return
      end

      simple_run_commands_with_output(
        options[:post_run_success],
        title: "post-run success",
        verbose:,
      )

      Notifier.notify(success: true)

      if dry_run
        puts "《 Dry run completed 》"
      else
        push_dir = worktree_path || original_dir
        Dir.chdir(push_dir) do
          if will_set_up_remote_branch
            puts "Setting up the remote branch..."
            Kernel.system("git", "push", "-u", "origin", original_branch)
          else
            Kernel.system("git", "push", "origin", "HEAD:#{original_branch}")
          end
        end

        puts "《 #{options[:success_emoji] || "🌺"} 》 Good job! You're doing great."
      end

      # Check for updates after a successful run (even in dry run mode)
      VersionChecker.print_message_if_new_version(VERSION)
    end
  end
end

GpushCli.run(ARGV) if __FILE__ == $PROGRAM_NAME
