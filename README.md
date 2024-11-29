# gPush

This repo contains files needed for the `gpush` script, which runs tests/linters/etc prior to git push in order to ensure better code

## Installation

tap into the nitidbit/gpush homebrew repo. You only need to do this once

```
brew tap nitidbit/gpush
```

install gpush OR upgrade to the latest version

```
brew install gpush
# OR
brew upgrade gpush
```

Note: to ensure the lastest version, `brew update` before installing. Brew will do this automatically if it has not been performed in the last 24 hours

## Use

### Running the command

run the command

```
gpush
```

while in a directory within your git repo

### Command line options

|                    |                                                                                           |
| ------------------ | ----------------------------------------------------------------------------------------- |
| --version          | print the current version                                                                 |
| -h, --help         | print the help documentation                                                              |
| --dry-run          | run pre_run_commands, parallel_run_commands, and post_run_commands without pushing to git |
| --config_file=FILE | use an alternate config file. Default is gpushrc(.yml \| .yaml)                           |

### Config: `gpushrc.yml` or `gpushrc.yaml`

Gpush will look for a config file in the current directory. If not found, it will traverse up the directory structure until it finds a config file reaches the root directory ("/"). If still not found, it will use a built-in default config file.

#### TODO: add documentation for the config file. The table below is out of date

#### TODO: add example config yaml inline here

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

### Notifications

Because builds can take a while, there is a notification system in place to let you know when the build is complete.
_This is a macOS only feature at this time._

You can suppress notifications by setting the env `GPUSH_NO_NOTIFIER=1` in your favorite shell configuration file.

Your preferred success or fail sound effects will play if you set env `GPUSH_SOUND_SUCCESS` and/or `GPUSH_SOUND_FAIL` to
the path of a sound file.

Default "tadaa!" and "wah-wah-waaah!" for these are included here, which you can use by
setting the env vars to `default`. These default sounds are from:

- [Pixabay, wah-wah-sad-trombone-6347](https://pixabay.com/sound-effects/wah-wah-sad-trombone-6347/) by kirbydx (Freesound)
- [Pixabay, tada-fanfare-a-6313](https://pixabay.com/sound-effects/tada-fanfare-a-6313/) by plasterbrain (Freesound)

## What actually happens during gPush?

See below image:
![Flow](https://github.com/nitidbit/gpush/blob/release/v2-hackathon/gpush_diagram.png?raw=true)

## Contributing

### Current issues

[Github Issues Page](https://github.com/nitidbit/gpush/issues)

### Install gpush using homebrew

clone the gpush repo (if you have not yet done so)

```
git clone https://github.com/nitidbit/gpush
```

Install (use `brew reinstall` if you already have a version of gpush installed)

```
brew install [path-to-local-gpush-repo]/Formula/gpush.rb
# OR
brew reinstall [path-to-local-gpush-repo]/Formula/gpush.rb
```

### Development

Edit the files in the src/ruby directory. To test your changes,

- write tests and use rspec `bundle exec rspec`
- reinstall the development version (see above) and run gpush --dry-run

### pushing changes

Gpush uses gpush! do not push directly to git, instead run `gpush`

### Publish a New Release Version

### Step 1: Prepare the release build

_In the `gpush` repository:_

- Commit Your Changes: Ensure all necessary changes are committed to your Git repository.
  Homebrew will pull exactly what's in the repository at the time of archiving.
- Find the _current_ version number with `brew info gpush`, let's call that `a.b.c`
- Run the release script, specifing the _new_ version number, let's call that `x.y.z`:
  - `ruby release.rb -v x.y.z`
- Take note of URL and SHA for the new release. The output will look like this:

```
  ================================================================================
  url "https://github.com/nitidbit/gpush/archive/refs/tags/vx.y.z.tar.gz"
  sha256 "18c50e59b66ff889c7720fec82899329c95eea28d32b12f34085cb96deadbeef"
  ================================================================================
```

### Step 2: Publish the release

_In the `homebrew-gpush` repository:_

- Save off the current release formula `cp Formula/gpush.rb Formula/gpush@a.b.c`
- edit `Formula/gpush.rb@a.b.c` change the classname to `GpushATabc` (e.g. `GpushAT123` for v1.2.3)
- edit `Formula/gpush.rb` update the 2 lines of `url` and `sha256` with the new values from the build
- `git commit -am"version x.y.z"`
- `git push`
- `brew update gpush`

## Homebrew Core Submission Next Steps:

Increase notability by upping GitHub stars, watchers, and forks

- [ ] Continue improvements and adding features, encourage users to watch the repository for updates
- [ ] Write documentation to make it easy for people to use
- [ ] Share project on forums/social media/blog posts to increase visibility
