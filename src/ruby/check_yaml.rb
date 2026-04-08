# frozen_string_literal: true

# Syntax-only check: parse YAML without deserializing to Ruby (no Date/safe_load issues).
# Only scans repo dirs that hold our configs — never vendor/ or node_modules/.

require "psych"

ROOTS = %w[. spec nitid_linter_configs].freeze
SKIP = %w[vendor node_modules .git].freeze

paths =
  ROOTS
    .flat_map do |root|
      next [] unless Dir.exist?(root)

      Dir.glob(File.join(root, "**", "*.{yml,yaml}"))
    end
    .reject { |p| p.split(File::SEPARATOR).intersect?(SKIP) }
    .uniq
    .sort

exit 0 if paths.empty?

paths.each do |path|
  next unless File.file?(path)

  Psych.parse_file(path)
rescue Psych::SyntaxError => e
  warn "#{path}: #{e.message}"
  exit 1
end
