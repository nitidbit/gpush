#!/usr/bin/env ruby

require "English"
REPO = "nitidbit/gpush".freeze # Updated with the correct repository name

def release
  # Step 1: Read version file
  version_file = File.read("./src/ruby/gpush.rb")
  unless version_file
    puts "Error: Failed to read the version file."
    exit 1
  end

  # Extract the version
  version = version_file.match(/VERSION\s*=\s*['"](.*)['"]/)
  unless version
    puts "Error: Failed to extract version from the version file."
    exit 1
  end

  version = version[1]
  puts "found version: #{version}"

  unless version.match?(/^\d+\.\d+\.\d+$/)
    puts "Error: Version #{version} is not a valid semantic version (X.Y.Z)."
    exit 1
  end
  tag = "v#{version}"

  # Step 2: Handle existing version tags
  existing_tags = `git tag`.split("\n")
  if existing_tags.empty?
    puts "Error: Failed to retrieve git tags."
    exit 1
  end

  if existing_tags.include?(tag)
    puts "Tag #{tag} already exists, skipping tag creation."
  else
    system("git tag -a #{tag} -m 'Release version #{tag}'")
    unless $CHILD_STATUS.success?
      puts "Error: Failed to create git tag #{tag}."
      exit 1
    end
  end

  # Step 2.1: Check remote for existing tags
  remote_tags =
    `git ls-remote --tags origin`.split("\n")
      .map { |line| line.split("\t").last.split("/").last }
  if remote_tags.include?(tag)
    puts "Tag #{tag} already exists on the remote, skipping tag push to origin."
  else
    system("git push origin #{tag}")
    unless $CHILD_STATUS.success?
      puts "Error: Failed to push git tag #{tag} to origin."
      exit 1
    end
  end

  # Step 4: Define the tarball URL and download the tarball
  tarball_url = "https://github.com/#{REPO}/archive/refs/tags/#{tag}.tar.gz"

  # Verify that the tarball URL is valid
  puts "Checking tarball URL: #{tarball_url}"
  response_code = `curl -o /dev/null -s -w "%{http_code}" #{tarball_url} -L`
  unless response_code == "200"
    puts "Error: Tarball URL returned #{response_code}. The file may not exist or be accessible."
    exit 1
  end

  system("curl -L -o #{tag}.tar.gz #{tarball_url}")
  unless $CHILD_STATUS.success?
    puts "Error: Failed to download tarball from #{tarball_url}."
    exit 1
  end

  # Step 5: Compute the SHA-256 checksum
  sha_256 = `shasum -a 256 #{tag}.tar.gz`.split.first
  unless sha_256
    puts "Error: Failed to compute SHA-256 checksum."
    exit 1
  end

  # Clean up the downloaded tarball
  system("rm #{tag}.tar.gz")
  unless $CHILD_STATUS.success?
    puts "Error: Failed to remove the downloaded tarball."
    exit 1
  end

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

release
