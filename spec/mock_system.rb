class MockSystem
  class MockChildStatus
    def initialize(success) = @success = success
    def success? = @success
  end

  attr_reader :commands, :responses

  DEFAULT_MOCKS = {
    "git rev-parse --is-inside-work-tree > /dev/null 2>&1" => {
      output: "",
      exit_code: 0,
    },
  }.freeze

  def initialize
    @commands = []
    @responses = DEFAULT_MOCKS.dup
  end

  def add_mock(command, output:, exit_code:)
    @responses[command] = { output: output, exit_code: exit_code }
  end

  def mocked_system_call(command)
    @commands << command
    if @responses[command]
      puts @responses[command][:output]
      $CHILD_STATUS = MockChildStatus.new(@responses[command][:exit_code].zero?)
      return @responses[command][:exit_code] == 0
    end

    raise "MockSystem: Command `#{command}` not found"
  end

  def reset
    @commands.clear
  end
end
