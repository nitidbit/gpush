# macOS native notifications of build status.
# This is quietly skipped if you set (any value) and export this ENV var in your favorite .rc file:
#   `export GPUSH_NO_NOTIFIER=1`
#
# Bonus effects for the inspired. If you set env vars GPUSH_SOUND_SUCCESS and/or GPUSH_SOUND_FAIL to the path
# of a sound file, they will be played as needed. Setting each of these to "default" will use the following built ins:
# https://pixabay.com/sound-effects/wah-wah-sad-trombone-6347/
# https://pixabay.com/sound-effects/tada-fanfare-a-6313/
#
# These features rely on the presence of `terminal-notifier` (installed here as a brew dependency)
# and `afplay` (part of macOS) commands.

# frozen_string_literal: true
module Notifier
  GPUSH_SOUND_SUCCESS = "GPUSH_SOUND_SUCCESS"
  GPUSH_SOUND_FAIL = "GPUSH_SOUND_FAIL"

  def self.notify(success: true, msg: "Finished!")
    audio_player = `which afplay`.chomp
    audio_player = nil if audio_player.empty?

    if audio_player
      maybe_play(audio_player, GPUSH_SOUND_SUCCESS, success)
      maybe_play(audio_player, GPUSH_SOUND_FAIL, !success)
    end

    terminal_notifier = `which terminal-notifier`.chomp
    terminal_notifier = nil if terminal_notifier.empty?

    return if terminal_notifier.nil? || ENV.key?("GPUSH_NO_NOTIFIER")

    subtitle = success ? "Success" : "Fail"
    sound = success ? "Hero" : "Basso"
    emojis = success ? "🥳🎉🍾" : "🤨💩🙈"

    args = [
      terminal_notifier,
      "-title",
      "GPush Build",
      "-subtitle",
      "#{emojis} #{subtitle} #{emojis}",
      "-message",
      msg.to_s,
      "-sound",
      sound,
      # "-sender",
      # "com.apple.terminal",
      "-group",
      "GPush",
      "--timeout",
      "5",
    ]

    system(*args)
  end

  def self.maybe_play(audio_player, env_var_name, play_if)
    if audio_player.nil? || !play_if ||
         ![GPUSH_SOUND_SUCCESS, GPUSH_SOUND_FAIL].include?(env_var_name) ||
         !ENV.key?(env_var_name)
      return
    end

    sound_file =
      if ENV.fetch(env_var_name) == "default"
        if env_var_name == GPUSH_SOUND_SUCCESS
          File.join(
            File.dirname(__FILE__),
            "../assets",
            "tada-fanfare-a-6313.mp3",
          )
        else
          File.join(
            File.dirname(__FILE__),
            "../assets",
            "wah-wah-sad-trombone-6347.mp3",
          )
        end
      else
        ENV.fetch(env_var_name)
      end

    return unless !sound_file.nil? && File.file?(sound_file)

    Process.spawn(audio_player, sound_file)
  end
end
