#!/usr/bin/env ruby

require "optparse"
require "English"

REPO = "nitidbit/gpush".freeze # Updated with the correct repository name

def release(version: nil)
  # Step 1: Extract or validate the version
  version ||= extract_version
  unless version.match?(/^\d+\.\d+\.\d+$/)
    puts "Error: Version #{version} is not a valid semantic version (X.Y.Z)."
    exit 1
  end

  tag = "v#{version}"
  puts "Using version: #{version}"

  # Step 2: Handle existing version tags
  existing_tags = `git tag`.split("\n")
  exit_with_error("Failed to retrieve git tags.") if existing_tags.empty?

  if existing_tags.include?(tag)
    puts "Tag #{tag} already exists, skipping tag creation."
  else
    system("git tag -a #{tag} -m 'Release version #{tag}'")
    unless $CHILD_STATUS.success?
      exit_with_error("Failed to create git tag #{tag}.")
    end
  end

  # Step 2.1: Check remote for existing tags
  remote_tags = fetch_remote_tags
  if remote_tags.include?(tag)
    puts "Tag #{tag} already exists on the remote, skipping tag push to origin."
  else
    system("git push origin #{tag}")
    unless $CHILD_STATUS.success?
      exit_with_error("Failed to push git tag #{tag} to origin.")
    end
  end

  # Step 4: Define the tarball URL and download the tarball
  tarball_url = "https://github.com/#{REPO}/archive/refs/tags/#{tag}.tar.gz"

  # Verify that the tarball URL is valid
  validate_tarball_url(tarball_url)

  # Step 5: Compute the SHA-256 checksum
  sha_256 = compute_sha256(tag, tarball_url)

  # Output the success message and formula details
  puts "Release #{tag} created successfully."
  puts "Update Formula/gpush.rb in the homebrew-gpush repo with:"
  puts "=" * 80
  puts <<~FORMULA
    url "#{tarball_url}"
    sha256 "#{sha_256}"
  FORMULA
  puts "=" * 80
  puts ""

  # Step 6: Provide manual release instructions
  puts <<~INSTRUCTION
    You need to manually publish the release on GitHub:
    1. Go to https://github.com/#{REPO}/releases
    2. Find the tag #{tag} (or draft a new release if necessary).
    3. Fill in the release notes and publish it.
  INSTRUCTION
end

def extract_version
  version_file = File.read("./src/ruby/gpush.rb")
  match = version_file.match(/VERSION\s*=\s*['"](.*)['"]/)
  return match[1] if match

  puts "Error: Failed to extract version from the version file."
  exit 1
end

def fetch_remote_tags
  `git ls-remote --tags origin`.split("\n")
    .map { |line| line.split("\t").last.split("/").last }
end

def validate_tarball_url(tarball_url)
  puts "Checking tarball URL: #{tarball_url}"
  response_code = `curl -o /dev/null -s -w "%{http_code}" #{tarball_url} -L`
  return if response_code == "200"

  puts "Error: Tarball URL returned #{response_code}. The file may not exist or be accessible."
  exit 1
end

def compute_sha256(tag, tarball_url)
  system("curl -L -o #{tag}.tar.gz #{tarball_url}")
  unless $CHILD_STATUS.success?
    exit_with_error("Failed to download tarball from #{tarball_url}.")
  end

  sha_256 = `shasum -a 256 #{tag}.tar.gz`.split.first
  exit_with_error("Failed to compute SHA-256 checksum.") unless sha_256

  system("rm #{tag}.tar.gz")
  unless $CHILD_STATUS.success?
    exit_with_error("Failed to remove the downloaded tarball.")
  end

  sha_256
end

def exit_with_error(message)
  puts "Error: #{message}"
  exit 1
end

# Parse CLI arguments
options = {}
OptionParser
  .new do |opts|
    opts.banner = "Usage: release.rb [options]"

    opts.on(
      "-v",
      "--version VERSION",
      "Specify the version to release (e.g., 2.5.0)",
    ) { |v| options[:version] = v }
  end
  .parse!

release(version: options[:version])
