require_relative 'gpush_error' # Import the custom error handling
module GitHelper
  def self.at_same_commit_as_remote_branch?
    system 'git fetch'
    return false unless remote_branch_name
    remote_commit = `git rev-parse @{u}`.strip
    local_commit = `git rev-parse @`.strip
    remote_commit == local_commit
  end

  def self.detached_head?
    branch = `git rev-parse --abbrev-ref HEAD`.strip
    branch == "HEAD"
  end

  def self.up_to_date_or_ahead_of_remote_branch?
    system 'git fetch'

    # Check if there's an upstream branch set
    return false unless remote_branch_name

    # Get the common ancestor (merge base) of the local and remote branches
    merge_base = `git merge-base @ @{u}`.strip
    remote_commit = `git rev-parse @{u}`.strip

    # If the merge base is the same as the remote commit, local is up-to-date or ahead
    merge_base == remote_commit
  rescue
    false  # Return false in case of an error
  end

  def self.remote_branch_name
    result = `git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null`.strip
    result.empty? ? nil : result
  end

  def self.behind_remote_branch?
    !up_to_date_or_ahead_of_remote_branch?
  end

  def self.ask_yes_no(question, default: nil)
    require 'io/console'  # Required to handle special key inputs like ESC

    print "#{question} (#{default == true ? 'Y' : 'y'}/#{default == false ? 'N' : 'n'}): "

    input = ""

    while input.empty?
      char = STDIN.getch

      # Check if Ctrl-C is pressed and raise Interrupt
      if char == "\u0003"
        raise Interrupt  # Allow Ctrl-C to behave as normal without interference
      end

      case char
      when "\r"  # Enter key
        puts "default is #{default}"
        return default if !default.nil?  # Return the default value if Enter is pressed
      when "\e"  # ESC key
        puts ""
        return false  # Return false if ESC is pressed
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

    question = 'No remote branch set. Create branch on origin if tests pass?'

    if ask_yes_no(question)
      return true
      # Later use this flag to set up the remote branch
    else
      raise GpushError, 'No remote branch setup.'
        # Stop further execution
    end
  end
end