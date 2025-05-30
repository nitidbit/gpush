require "English"
require_relative "gpush_error" # Import the custom error handling
require "open3"

module GitHelper
  def self.git_root_dir
    stdout, stderr, status = Open3.capture3("git rev-parse --show-toplevel")
    return stdout.strip if status.success?
    raise GpushError, stderr.strip
  end

  def self.exit_with_error(error)
    puts "\n\nGpush encountered an error:"
    puts error.message
    puts "\nExiting gpush."
    exit 1
  end

  def self.at_same_commit_as_remote_branch?
    Kernel.system "git fetch"
    return false unless remote_branch_name
    remote_commit = `git rev-parse @{u}`.strip
    local_commit = `git rev-parse @`.strip
    remote_commit == local_commit
  end

  def self.detached_head?
    `git rev-parse --abbrev-ref HEAD`.strip == "HEAD"
  end

  def self.not_a_git_repository?
    Kernel.system("git rev-parse --is-inside-work-tree > /dev/null 2>&1")
    !$CHILD_STATUS.success?
  end

  def self.up_to_date_or_ahead_of_remote_branch?
    Kernel.system "git fetch"

    # Check if there's an upstream branch set
    return false unless remote_branch_name

    # Get the common ancestor (merge base) of the local and remote branches
    merge_base = `git merge-base @ @{u}`.strip
    remote_commit = `git rev-parse @{u}`.strip

    # If the merge base is the same as the remote commit, local is up-to-date or ahead
    merge_base == remote_commit
  rescue StandardError
    false # Return false in case of an error
  end

  def self.remote_branch_name
    result =
      `git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null`.strip
    result.empty? ? nil : result
  end

  def self.local_branch_name
    `git rev-parse --abbrev-ref HEAD`.strip
  end

  def self.branch_exists_on_origin?(branch_name)
    # Use git ls-remote to check if the branch exists on origin
    result = `git ls-remote --heads origin #{branch_name}`.strip
    !result.empty?
  end

  def self.behind_remote_branch?
    !up_to_date_or_ahead_of_remote_branch?
  end

  def self.ask_yes_no(question, default: nil)
    require "io/console" # Required to handle special key inputs like ESC

    print "#{question} (#{default == true ? "Y" : "y"}/#{default == false ? "N" : "n"}): "

    input = ""

    while input.empty?
      char = $stdin.getch

      # Check if Ctrl-C is pressed and raise Interrupt
      if char == "\u0003"
        raise Interrupt # Allow Ctrl-C to behave as normal without interference
      end

      case char
      when "\r" # Enter key
        return default unless default.nil? # Return the default value if Enter is pressed
      when "\e" # ESC key
        puts ""
        return false # Return false if ESC is pressed
      when "y", "Y"
        puts "y"
        return true
      when "n", "N"
        puts "n"
        return false
      end
    end
  end

  def self.user_wants_to_set_up_remote_branch?
    return false if remote_branch_name

    question = "No remote branch set. Create branch on origin if tests pass?"

    return true if ask_yes_no(question)

    # Later use this flag to set up the remote branch

    raise GpushError, "No remote branch setup."
    # Stop further execution
  end

  def system = raise "use Kernel.system (makes testing easier)"
  def self.system = raise "use Kernel.system (makes testing easier)"
end
