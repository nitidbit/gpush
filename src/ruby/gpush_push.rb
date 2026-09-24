# frozen_string_literal: true

require_relative "exit_helper"

# The push at the end of a gpush run, and the post_push_* sections after it.
class GpushPush
  PUSH_FAILED_MESSAGE =
    "\ngit push failed. Your checks passed, but nothing was pushed."

  def initialize(options, branch:, push_dir:, tested_sha:, in_worktree:)
    @options = options
    @branch = branch
    @push_dir = push_dir
    @tested_sha = tested_sha
    @in_worktree = in_worktree
  end

  def run(set_up_remote_branch:)
    puts "Setting up the remote branch..." if set_up_remote_branch

    unless push
      run_post_push_commands(
        :post_push_failure,
        title: "post-push failure",
        failure_note: PUSH_FAILED_MESSAGE,
      )
      puts PUSH_FAILED_MESSAGE
      ExitHelper.exit 1
    end

    track_remote_branch if set_up_remote_branch
    run_post_push_commands(
      :post_push_success,
      title: "post-push success",
      failure_note: "The push itself succeeded: origin/#{@branch} is updated.",
    )

    puts ""
    puts "《 #{@options[:success_emoji] || "🌺"} 》 Good job! You're doing great."
    puts ""
  end

  private

  def push
    # Push HEAD rather than the branch, which may have moved on while the
    # checks ran, and spell out refs/heads, which git requires of a
    # destination that is not on the remote yet. A worktree is detached,
    # so its upstream is set afterwards rather than with push -u.
    push_args = ["origin", "HEAD:refs/heads/#{@branch}"]
    # Only the push (and the post-push sections) get this, so a pre-push
    # hook can tell a gpush push (checks already passed) from any other
    # push made along the way.
    push_env = { "GPUSH_TESTED_SHA" => @tested_sha }
    Dir.chdir(@push_dir) { Kernel.system(push_env, "git", "push", *push_args) }
  end

  def track_remote_branch
    if Kernel.system(
         "git",
         "branch",
         "--set-upstream-to=origin/#{@branch}",
         @branch,
       )
      return
    end

    puts "Pushed origin/#{@branch}, but could not set it as the upstream."
  end

  def run_post_push_commands(section, title:, failure_note:)
    Dir.chdir(@push_dir)
    with_env("GPUSH_BRANCH" => @branch, "GPUSH_TESTED_SHA" => @tested_sha) do
      Gpush.simple_run_commands_with_output(
        Gpush.filter_commands(@options[section], in_worktree: @in_worktree),
        title:,
        verbose: @options[:verbose],
        spinner: @options[:spinner] != false,
        failure_note:,
      )
    end
  end

  def with_env(vars)
    originals = vars.keys.to_h { |key| [key, ENV.fetch(key, nil)] }
    ENV.update(vars)
    yield
  ensure
    ENV.update(originals)
  end
end
