# frozen_string_literal: true

# Wrapping for --help output. Every command's help is held to WIDTH columns by
# spec/help_width_spec.rb, so descriptions are written here as one long string
# and split at render time rather than hand-broken in the source, where the
# breaks go stale the first time someone rewords them.
module HelpText
  WIDTH = 80

  # The column OptionParser starts an option's description in: its
  # summary_indent (4) plus its summary_width (32) plus the separating space.
  # Pass this as `indent` when wrapping text handed to opts.on.
  OPTION_INDENT = 37

  # Split text into lines that fit within WIDTH once indented by `indent`.
  # A single word longer than the available room gets its own line and
  # overflows; nothing is truncated or hyphenated.
  def self.wrap(text, indent: 0)
    limit = WIDTH - indent
    text
      .split(/\s+/)
      .reject(&:empty?)
      .each_with_object([]) do |word, lines|
        if lines.empty? || lines.last.length + 1 + word.length > limit
          lines << +word
        else
          lines.last << " " << word
        end
      end
  end

  # Wrap text into a single string whose continuation lines are indented to
  # hang under where the first line's text began.
  def self.hanging(text, indent: 0)
    wrap(text, indent:).join("\n#{" " * indent}")
  end

  # Wrap a description for opts.on, which renders each string it is given on
  # its own line. Splat the result: opts.on("--flag", *HelpText.option("..."))
  def self.option(text)
    wrap(text, indent: OPTION_INDENT)
  end
end
