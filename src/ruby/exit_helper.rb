module ExitHelper
  # makes testing easier by allowing us to mock the exit method
  def self.exit(code) # rubocop:disable Lint/UselessMethodDefinition
    super
  end

  def self.exit_with_error(error)
    puts "\n\nGpush encountered an error:"
    puts error.message
    puts "\nExiting gpush."
    exit 1
  end
end
