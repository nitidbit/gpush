module GitHelper
  def self.at_same_commit_as_remote_branch?
    system 'git fetch'
    return false unless remote_branch_name
    remote_commit = `git rev-parse @{u}`.strip
    local_commit = `git rev-parse @`.strip
    remote_commit == local_commit
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

  def self.check_remote_branch
    setup_remote_branch = false

    if remote_branch_name
      if up_to_date_or_ahead_of_remote_branch?
        puts "gpush: Local branch is up to date with the remote branch '#{remote_branch_name}'."
        # Continue with your operations below
      else
        raise 'GpushError: Local branch is not up to date with the remote branch. Exiting.'
        # Stop further execution
      end
    else
      print 'No remote branch set. Create branch on origin if tests pass? (y/n): '
      user_input = gets.chomp.downcase

      if user_input == 'y'
        setup_remote_branch = true
        # Later use this flag to set up the remote branch
      else
        raise 'GpushError: No remote branch setup.'
        # Stop further execution
      end
    end

    setup_remote_branch
  end
end
