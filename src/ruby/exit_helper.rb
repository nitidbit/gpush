module ExitHelper
  # makes testing easier by allowing us to mock the exit method
  def self.exit(code) # rubocop:disable Lint/UselessMethodDefinition
    super
  end
end
