require "spec_helper"
require "tmpdir"
require_relative "../src/ruby/gpush.rb"

RSpec.describe InterruptController do
  around do |example|
    original_handler = Signal.trap("INT", "DEFAULT")
    example.run
  ensure
    InterruptController.uninstall
    Signal.trap("INT", original_handler)
  end

  before do
    Dir.chdir(__dir__)
    stub_const("InterruptController::STOP_GRACE_SECONDS", 0.3)
  end

  let(:dir) { Dir.mktmpdir }

  def path(name) = File.join(dir, name)

  def pid_in(name) = File.read(path(name)).to_i

  # A killed process stays a zombie until its thread reaps it, which is as
  # good as gone
  def alive?(pid)
    state = `ps -o stat= -p #{pid}`.strip
    !state.empty? && !state.start_with?("Z")
  end

  def press_ctrl_c = Process.kill("INT", Process.pid)

  # Presses Ctrl-C `times` times once every named file has been written
  def press_once_written(*names, times: 1)
    Thread.new do
      sleep 0.05 until names.all? { |name| File.size?(path(name)) }
      times.times do
        press_ctrl_c
        sleep 0.2
      end
    end
  end

  def parallel(*commands) =
    Command.run_in_parallel?(commands, options: { spinner: false })

  it "restores the previous handler when uninstalled" do
    previous_handler = proc {}
    Signal.trap("INT", previous_handler)

    InterruptController.install
    InterruptController.uninstall

    expect(Signal.trap("INT", "DEFAULT")).to eq(previous_handler)
  end

  context "when installed to be patient, as for cleanup" do
    before { InterruptController.install(patient: true) }

    let(:stubborn) { "trap '' INT; echo $$ > #{path("a")}; sleep 30" }

    it "runs a cleanup command's if check out of reach of a terminal Ctrl-C" do
      command =
        Command.new(
          {
            "name" => "checked",
            "if" => "echo $$ > #{path("a")}; sleep 0.3",
            "shell" => "true",
          },
        )
      group = nil
      Thread.new do
        sleep 0.05 until File.size?(path("a"))
        group = Process.getpgid(pid_in("a"))
      end

      InterruptController.current.section { command.run }

      expect(group).not_to eq(Process.getpgrp)
      expect(command.status).to eq("success")
    end

    it "stops a hung cleanup if check on the second Ctrl-C" do
      command =
        Command.new(
          {
            "name" => "checked",
            "if" => "echo $$ > #{path("a")}; exec sleep 30",
            "shell" => "true",
          },
        )
      press_once_written("a", times: 2)

      expect { InterruptController.current.section { command.run } }.to output(
        /Stopping the running cleanup command/,
      ).to_stdout
      expect(command.status).to eq("interrupted")
    end

    it "lets every cleanup command finish when an Interrupt is pending" do
      first =
        Command.new({ "shell" => "sleep 0.4; echo FIRST-RAN" }, verbose: true)
      second = Command.new({ "shell" => "echo SECOND-RAN" }, verbose: true)
      main = Thread.current
      Thread.new do
        sleep 0.2
        main.raise Interrupt
      end

      expect {
        Thread.handle_interrupt(Interrupt => :never) do
          InterruptController.current.section { first.run }
          InterruptController.current.section { second.run }
        end
      }.to raise_error(Interrupt).and output(/FIRST-RAN.*SECOND-RAN/m).to_stdout
    end

    it "only warns on the first Ctrl-C" do
      press_once_written("a")

      Thread.new do
        sleep 0.05 until File.size?(path("a"))
        sleep 0.5
        Process.kill("KILL", pid_in("a"))
      end
      expect {
        InterruptController.current.section do
          Command.new({ "shell" => stubborn }).run
        end
      }.to output(/Ctrl-C ignored until cleanup finishes/).to_stdout
    end

    it "stops the current command on a second Ctrl-C, without quitting" do
      press_once_written("a", times: 2)
      command = Command.new({ "shell" => stubborn })

      expect { InterruptController.current.section { command.run } }.to output(
        /Stopping the running cleanup command/,
      ).to_stdout

      expect(command.success?).to be(false)
      expect(alive?(pid_in("a"))).to be(false)
    end

    it "stops each later command with a single Ctrl-C once it has warned" do
      press_once_written("a")
      Thread.new do
        sleep 0.05 until File.size?(path("a"))
        sleep 0.3
        Process.kill("KILL", pid_in("a"))
      end
      first = Command.new({ "shell" => stubborn })
      second =
        Command.new(
          { "shell" => "trap '' INT; echo $$ > #{path("b")}; sleep 30" },
        )

      expect {
        InterruptController.current.section { first.run }
        press_once_written("b")
        InterruptController.current.section { second.run }
      }.to output(/Stopping the running cleanup command/).to_stdout

      expect(second.success?).to be(false)
      expect(alive?(pid_in("b"))).to be(false)
    end
  end

  context "when installed" do
    before { InterruptController.install }

    it "interrupts the running commands on the first Ctrl-C" do
      press_once_written("a")
      result = nil

      expect {
        result =
          parallel(
            {
              "name" => "slow",
              "shell" => "echo $$ > #{path("a")}; exec sleep 30",
            },
          )
      }.to output(/attempting to stop gracefully/).to_stdout

      expect(result).to be(false)
      expect(alive?(pid_in("a"))).to be(false)
    end

    it "doesn't start a command in a section once it was interrupted" do
      press_once_written("a")

      expect {
        parallel(
          {
            "name" => "slow",
            "shell" => "echo $$ > #{path("a")}; exec sleep 30",
          },
          {
            "name" => "late",
            "if" => "sleep 1",
            "shell" => "touch #{path("late")}",
          },
        )
      }.to output.to_stdout

      expect(File.exist?(path("late"))).to be(false)
    end

    it "runs the next section normally after an interrupted one" do
      press_once_written("a")
      expect {
        parallel(
          {
            "name" => "slow",
            "shell" => "echo $$ > #{path("a")}; exec sleep 30",
          },
        )
      }.to output.to_stdout

      expect {
        Gpush.simple_run_commands_with_output(
          [{ "name" => "next", "shell" => "touch #{path("next")}" }],
          title: "post-run",
          options: {
          },
        )
      }.to output.to_stdout

      expect(File.exist?(path("next"))).to be(true)
    end

    it "force quits on a second Ctrl-C, killing each command's whole process group" do
      stubborn =
        "trap '' INT; (trap '' INT; exec sleep 30) & echo $! > #{path("child")}; " \
          "echo $$ > #{path("a")}; wait"
      press_once_written("a", "child", times: 2)

      expect {
        parallel({ "name" => "stubborn", "shell" => stubborn })
      }.to raise_error(Interrupt).and output(/Force quitting/).to_stdout

      expect(alive?(pid_in("a"))).to be(false)
      expect(alive?(pid_in("child"))).to be(false)
    end

    it "stops what an interrupted command leaves behind in its process group" do
      # The shell exits on Ctrl-C, but leaves a child that ignores it (and the
      # hangup the PTY sends its session when the shell exits)
      leaves_child =
        "(trap '' INT HUP; exec sleep 30) & echo $! > #{path("child")}; " \
          "echo $$ > #{path("a")}; wait"
      press_once_written("a", "child")

      expect {
        Gpush.simple_run_commands_with_output(
          [{ "name" => "leaves child", "shell" => leaves_child }],
          title: "pre-run",
          options: {
          },
        )
      }.to raise_error("Exit called with code 1").and output(
              /pre-run command interrupted - leaves child/,
            ).to_stdout

      expect(alive?(pid_in("child"))).to be(false)
    end

    it "reports a command whose if check was interrupted as interrupted, not skipped" do
      # A terminal Ctrl-C reaches gpush and its foreground `if` check alike
      Thread.new do
        sleep 0.05 until File.size?(path("a"))
        press_ctrl_c
        Process.kill("INT", pid_in("a"))
      end
      result = nil

      expect {
        result =
          parallel(
            {
              "name" => "checked",
              "if" => "echo $$ > #{path("a")}; exec sleep 30",
              "shell" => "true",
            },
          )
      }.to output(/checked: .*INTERRUPTED/).to_stdout

      expect(result).to be(false)
    end

    it "fails parallel_run when Ctrl-C lands as its commands finish" do
      result = nil

      expect {
        result =
          parallel(
            {
              "name" => "quick",
              "shell" => "trap '' INT; kill -INT $PPID; sleep 0.3",
            },
          )
      }.to output(/Interruption detected/).to_stdout

      expect(result).to be(false)
    end

    it "halts a sequential section when Ctrl-C lands as its commands finish" do
      expect {
        Gpush.simple_run_commands_with_output(
          [
            {
              "name" => "quick",
              "shell" => "trap '' INT; kill -INT $PPID; sleep 0.3",
            },
          ],
          title: "pre-run",
          options: {
          },
        )
      }.to raise_error("Exit called with code 1").and output(
              /pre-run was interrupted/,
            ).to_stdout
    end

    it "keeps a command's controller, so it can't start after a force quit" do
      command = Command.new({ "shell" => "touch #{path("late")}" })
      InterruptController.current.instance_variable_set(:@force_quitting, true)
      InterruptController.current.instance_variable_set(
        :@interrupt_raised,
        true,
      )
      InterruptController.uninstall

      command.run

      expect(command.status).to eq("interrupted")
      expect(File.exist?(path("late"))).to be(false)
    end

    it "counts an if check that can't start as interrupted once Ctrl-C was pressed" do
      command =
        Command.new(
          {
            "name" => "checked",
            "if" => "gpush-no-such-tool",
            "shell" => "true",
          },
        )

      expect {
        InterruptController.current.section do
          parallel_started = Thread.new { sleep 30 }
          press_ctrl_c
          sleep 0.2
          command.run
        ensure
          parallel_started.kill
        end
      }.to output(/attempting to stop gracefully/).to_stdout
      expect(command.status).to eq("interrupted")
    end

    it "shows an interrupted sequential command's output" do
      expect {
        Gpush.simple_run_commands_with_output(
          [
            {
              "name" => "partial",
              "shell" => "echo PARTIAL-OUTPUT; kill -INT $PPID; sleep 5",
            },
          ],
          title: "pre-run",
          options: {
          },
        )
      }.to raise_error("Exit called with code 1").and output(
              /PARTIAL-OUTPUT/,
            ).to_stdout
    end

    it "stops a section's commands when it is left by an error, not Ctrl-C" do
      expect {
        InterruptController.current.section do
          Thread.new do
            Command.new(
              { "shell" => "echo $$ > #{path("a")}; exec sleep 30" },
            ).run
          end
          sleep 0.05 until File.size?(path("a"))
          raise IOError, "stdout went away"
        end
      }.to raise_error(IOError)

      expect(alive?(pid_in("a"))).to be(false)
    end

    it "keeps answering Ctrl-C if its watcher dies" do
      InterruptController.current.instance_variable_get(:@watcher).kill
      sleep 0.05

      expect {
        press_ctrl_c
        sleep 2
      }.to raise_error(Interrupt)
    end

    it "stops gracefully when the section's commands are still in their if check" do
      Thread.new do
        sleep 0.3
        press_ctrl_c
      end
      result = nil

      expect {
        result =
          parallel(
            {
              "name" => "late",
              "if" => "sleep 1",
              "shell" => "touch #{path("late")}",
            },
          )
      }.to output(/attempting to stop gracefully/).to_stdout

      expect(result).to be(false)
      expect(File.exist?(path("late"))).to be(false)
    end

    it "force quits on a Ctrl-C with nothing running" do
      expect {
        press_ctrl_c
        sleep 2
      }.to raise_error(Interrupt).and output(/Force quitting/).to_stdout
    end
  end
end
