# OSX native notifications of build status.
# This is quietly skipped if you set (any value) and export this ENV var in your favorite .rc file:
#   `export GPUSH_NO_NOTIFIER=1`
# This only works (and is quietly skipped otherwise) if you install `terminal-notifier` with your favorite packager:
#   `brew install terminal-notifier`
#
# Bonus effects for the inspired. If you set env vars GPUSH_SOUND_SUCCESS and/or GPUSH_SOUND_FAIL to the path
# of a sound file, they will be played as needed. Suggest these two solid options:
# https://pixabay.com/sound-effects/wah-wah-sad-trombone-6347/
# https://pixabay.com/sound-effects/tada-fanfare-a-6313/
# These could be baked into gpush, but grabbing your own favorites seems more fun.

# frozen_string_literal: true
module Notifier
  def self.notify(success = true, msg = "Finished!")
    audio_player = `which afplay`.chomp
    audio_player = nil if audio_player.empty?

    if audio_player
      if ENV.key?("GPUSH_SOUND_SUCCESS") && File.file?(ENV["GPUSH_SOUND_SUCCESS"]) && success
        Process.spawn(audio_player, ENV["GPUSH_SOUND_SUCCESS"])
      end

      if ENV.key?("GPUSH_SOUND_FAIL") && File.file?(ENV["GPUSH_SOUND_FAIL"]) && !success
        Process.spawn(audio_player, ENV["GPUSH_SOUND_FAIL"])
      end
    end

    terminal_notifier = `which terminal-notifier`.chomp
    terminal_notifier = nil if terminal_notifier.empty?

    return if terminal_notifier.nil? || ENV.key?("GPUSH_NO_NOTIFIER")

    subtitle = success ? "Success" : "Fail"
    sound = success ? "Hero" : "Basso"
    emojis = success ? "🥳🎉🍾" : "🤨💩🙈"

    args = [
      terminal_notifier,
      '-title', 'GPush Build',
      '-subtitle', "#{emojis} #{subtitle} #{emojis}",
      '-message', msg.to_s,
      '-sound', sound,
      '-sender', 'com.apple.terminal'
    ]

    system(*args)
  end
end
