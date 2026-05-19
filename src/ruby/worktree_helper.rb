# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"
require_relative "gpush_error"

module WorktreeHelper
  def self.create
    path = File.join(Dir.tmpdir, "gpush-#{Process.pid}-#{Time.now.to_i}")

    _, stderr, status =
      Open3.capture3("git", "worktree", "add", "--detach", path)
    unless status.success?
      raise GpushError, "Failed to create git worktree: #{stderr.strip}"
    end

    path
  end

  def self.copy_gitignored(git_root:, worktree_path:, globs: true)
    stdout, status =
      Open3.capture2(
        "git",
        "ls-files",
        "--others",
        "--ignored",
        "--exclude-standard",
        "--directory",
        chdir: git_root,
      )
    raise GpushError, "Failed to list gitignored files" unless status.success?

    glob_list =
      case globs
      when true
        nil
      when String
        [globs]
      when Array
        globs
      end

    stdout
      .split("\n")
      .each do |entry|
        bare = entry.chomp("/")
        if glob_list&.none? { |g|
             File.fnmatch(g, bare, File::FNM_PATHNAME) ||
               File.fnmatch(g, entry, File::FNM_PATHNAME)
           }
          next
        end

        src = File.join(git_root, bare)
        dest = File.join(worktree_path, bare)
        next unless File.exist?(src)
        next if File.exist?(dest)
        if File.directory?(src)
          flags = RUBY_PLATFORM.include?("darwin") ? "-Rc" : "-r"
          unless Kernel.system("cp", flags, src, dest)
            raise GpushError, "Failed to copy #{src} into worktree"
          end
        else
          begin
            FileUtils.cp(src, dest)
          rescue SystemCallError => e
            raise GpushError, "Failed to copy #{src} into worktree: #{e}"
          end
        end
      end
  end

  def self.remove(path)
    return unless path
    Kernel.system(
      "git",
      "worktree",
      "remove",
      "--force",
      path,
      out: File::NULL,
      err: File::NULL,
    )
  end
end
