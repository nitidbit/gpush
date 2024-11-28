# gPush

This repo contains files needed for the `gpush` script, which runs tests/linters/etc prior to git push in order to ensure better code

## User Setup

### Install gpush using homebrew

clone the gpush repo (if you have not yet done so)

```
git clone https://github.com/nitidbit/gpush
```

Install (use `brew reinstall` to update to a new version)

```
brew install [path-to-local-gpush-repo]/Formula/gpush.rb
```

## Developer Setup

[Here are the stories/tickets we are working on:](https://github.com/orgs/nitidbit/projects/3)

### Run

run the command `gpush`

### gpush settings `gpushrc.yml`

| **config key**      | **type**           | **values**                              |
| :------------------ | ------------------ | :-------------------------------------- |
| root_dir            | string             | path to working directory               |
| pre_run             | string or [string] |                                         |
| post_run            | string or [string] |                                         |
| import              | string or [string] | array of file paths or single file path |
| shell               | string             | shell commands to execute               |
| <NAME>              | string             | sets environment <NAME> to string       |
| if                  | string             | conditional shell expression            |
| command_definitions | object             | definition of a command                 |

### linter configurations

- eslint (for JavaScript & TypeScript)
  - `.eslintrc.json`
  - `.eslint_typescript.json`
- rubocop (for Ruby)
  - `.rubocop.yml`
- stylelint (for Scss)
  - `.stylelintrc.js`
  - `.stylelintrc.json`
  - _plugin_: `stylelint_plugin_nitid_use_stylekit.js`

### prettier (code formatter) configuration

- _usage_: JavaScript & TypeScript, Ruby, and potentially Scss
- _note_: for convenience, you can use prettier the following ways:
  - set up "format-on-save" in your IDE. See [here](https://www.educative.io/answers/how-to-set-up-prettier-and-automatic-formatting-on-vs-code)
  - call`lint.py` (work-in-progress) for autofixes.
- `.prettierrc.json`

## What actually happens during gPush?

See below image:
![Flow](https://github.com/nitidbit/gpush/blob/release/v2-hackathon/gpush_diagram.png?raw=true)

## How to Create a New Release Version

### Step 1: Prepare the release build

*In the `gpush` repository:*

- Commit Your Changes: Ensure all necessary changes are committed to your Git repository. 
  Homebrew will pull exactly what's in the repository at the time of archiving.
- Find the *current* version number with `brew info gpush`, let's call that `a.b.c`
- Prepare the release build and specify the *new* version number, let's call that `x.y.z`: `ruby release.rb -v x.y.z`
- Take note of URL and SHA for the new release. The output will look like this:
```
  ================================================================================
  url "https://github.com/nitidbit/gpush/archive/refs/tags/vx.y.z.tar.gz"
  sha256 "18c50e59b66ff889c7720fec82899329c95eea28d32b12f34085cb96deadbeef"
  ================================================================================
```

### Step 2: Publish the release

*In the `homebrew-gpush` repository:*

- Save off the current release formula `cp Formula/gpush.rb Formula/gpush@a.b.c`
- edit `Formula/gpush.rb@a.b.c` change the classname to `GpushATabc` (e.g. `GpushAT123` for v1.2.3)
- edit `Formula/gpush.rb` update the 2 lines of `url` and `sha256` with the new values from the build
- `git commit -am"version x.y.z"`
- `git push`
- `brew update gpush`

## Notifications

Because builds can take a while, there is a notification system in place to let you know when the build is complete.
*This is a macOS only feature at this time.*

You can suppress notifications by setting the env `GPUSH_NO_NOTIFIER=1` in your favorite shell configuration file.

Your preferred success or fail sound effects will play if you set env `GPUSH_SOUND_SUCCESS` and/or `GPUSH_SOUND_FAIL` to
the path of a sound file. 

Default "tadaa!" and "wah-wah-waaah!" for these are included here, which you can use by
setting the env vars to `default`. These default sounds are from:

 - [Pixabay, wah-wah-sad-trombone-6347](https://pixabay.com/sound-effects/wah-wah-sad-trombone-6347/) by kirbydx (Freesound)
 - [Pixabay, tada-fanfare-a-6313](https://pixabay.com/sound-effects/tada-fanfare-a-6313/) by plasterbrain (Freesound)

## Homebrew Core Submission Next Steps:

Increase notability by upping GitHub stars, watchers, and forks
- [ ] Continue improvements and adding features, encourage users to watch the repository for updates
- [ ] Write documentation to make it easy for people to use
- [ ] Share project on forums/social media/blog posts to increase visibility
