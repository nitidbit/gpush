# frozen_string_literal: true

# Version only (avoids requiring gpush.rb from gpush_changed_files / options parser).

DEFAULT_VERSION = "local-development"
VERSION = ENV["GPUSH_VERSION"] || DEFAULT_VERSION
