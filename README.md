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

|                                    |                                                                                                           |
| ---------------------------------- | --------------------------------------------------------------------------------------------------------- |
| --version                          | print the current version                                                                                 |
| -h, --help                         | print the help documentation                                                                              |
| --dry-run                          | run pre_run, parallel_run, and post_run without pushing to git                                            |
| --config-file=FILE                 | use an alternate config file. Default is gpushrc(.yml \| .yaml)                                           |
| --spinner / --no-spinner           | show/hide the live single-line spinner while commands run (overrides config)                              |
| --worktree / --no-worktree         | run checks in an isolated git worktree (overrides config)                                                 |
| --worktree-copy-gitignored[=GLOBS] | copy gitignored files into the worktree; optionally comma-separated globs (e.g. `config/master.key,.env`) |
| --no-worktree-copy-gitignored      | skip copying gitignored files into the worktree                                                           |

### Subcommands

`gpush SUBCOMMAND --help` documents each of `run`, `fix`, `diff-branch`, `changed-files`, `get-specs`, and `claude-review`.

#### `claude-review`

Reviews the branch diff — the `diff-branch` base to `HEAD` — with the Claude CLI, streaming the review to your terminal and exiting non-zero on blocking findings, so it works as a `parallel_run` check like any other.

| mode                    | skill              | per-repo guidance |
| :---------------------- | :----------------- | :---------------- |
| `--mode=code` (default) | `/code-review`     | `REVIEW.md`       |
| `--mode=security`       | `/security-review` | `SECURITY.md`     |

If the guidance file exists at the repository root, the review reads it and follows it — so your review conventions live in the repo, next to the code they apply to.

The review loads no Claude settings files and inherits none of your local permissions. It can read the repo and run read-only git commands, nothing else. A project that needs more can grant it with `--allowed-tools` in `gpushrc.yml`, where the grant is committed and so applies identically for everyone.

`--effort=low|medium|high|xhigh|max` (default `medium`) tunes review depth. `--instructions=TEXT` and `--instructions-file=FILE` append extra guidance to the prompt in the order given; both are repeatable.

### Exit codes

`gpush` exits **0** when every check passed — whether it pushed or ran with `--dry-run` — and **1** when anything failed: a check failed, `git push` was rejected, the git state was unusable, or the config was invalid. A failing check always exits 1; the individual command's own exit code is not passed through.

Answering "no" to a prompt (`Run tests anyway?`) exits 0. That is a deliberate stop, not a failure.

Subcommands report their own result:

| subcommand                   | 0                         | 1                  | other                                                                              |
| :--------------------------- | :------------------------ | :----------------- | :--------------------------------------------------------------------------------- |
| `changed-files`, `get-specs` | found something (printed) | found nothing      | `changed-files` exits 2 if the base branch cannot be resolved                      |
| `fix`, `run`                 | every command passed      | any command failed |                                                                                    |
| `diff-branch`                | printed the base branch   | bad arguments      |                                                                                    |
| `claude-review`              | no blocking findings      | blocking findings  | 2 tooling/access (from Claude), 3 no usable EXIT (CLI failure or malformed output) |

**`changed-files` and `get-specs` exit 1 to mean "nothing matched", not "something went wrong."** That is what makes them usable directly as an `if:` condition — see below.

### Config: `gpushrc.yml` or `gpushrc.yaml`

Gpush will look for a config file in the current directory. If not found, it will traverse up the directory structure until it finds a config file reaches the root directory ("/"). If still not found, it will use a built-in default config file.

#### Config keys

| **config key**             | **type**             | **description**                                                                                                                                                                                                                                                                                                                                                        |
| :------------------------- | -------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `pre_run`                  | list of commands     | run before parallel checks                                                                                                                                                                                                                                                                                                                                             |
| `parallel_run`             | list of commands     | run in parallel (main test/lint suite)                                                                                                                                                                                                                                                                                                                                 |
| `post_run`                 | list of commands     | run after parallel checks, regardless of result                                                                                                                                                                                                                                                                                                                        |
| `post_run_success`         | list of commands     | run only if all checks passed                                                                                                                                                                                                                                                                                                                                          |
| `post_run_failure`         | list of commands     | run only if any check failed                                                                                                                                                                                                                                                                                                                                           |
| `spinner`                  | boolean              | show the live single-line spinner while commands run (default `true`). Set to `false` for CI or piped logs.                                                                                                                                                                                                                                                            |
| `worktree`                 | boolean              | run checks in an isolated git worktree                                                                                                                                                                                                                                                                                                                                 |
| `worktree_copy_gitignored` | boolean or glob/list | copy gitignored files into the worktree. `true` copies all; a string or list of strings copies matching files only (e.g. `["config/master.key", ".env"]`). **Note:** globs must match top-level gitignored entries — files nested inside a fully-gitignored directory (e.g. `secrets/config/master.key` when `secrets/` is gitignored as a whole) will not be matched. |
| `success_emoji`            | string               | emoji printed on success (default 🌺)                                                                                                                                                                                                                                                                                                                                  |
| `gpush_version`            | string or list       | required gpush version constraint (e.g. `">= 2.0"`)                                                                                                                                                                                                                                                                                                                    |
| `verbose`                  | boolean              | print command output while running, as if `--verbose` were passed                                                                                                                                                                                                                                                                                                      |
| `fix`                      | list of commands     | commands run by `gpush fix`, in order. Not part of the normal `gpush` run.                                                                                                                                                                                                                                                                                             |
| `get_specs`                | hash                 | settings for `gpush get-specs` (e.g. `include_pattern`, `exclude_words`). Run `gpush get-specs --help` for the full list — every flag there has a matching key here.                                                                                                                                                                                                   |
| `gpush_changed_files`      | hash                 | settings for `gpush changed-files` (e.g. `fallback_branches`, `pattern`). Run `gpush changed-files --help` for the full list — every flag there has a matching key here.                                                                                                                                                                                               |

Any other top-level key is ignored, with a warning naming the key.

#### Command keys

Each entry in `pre_run`, `parallel_run`, `post_run`, `post_run_success`, `post_run_failure`, and `fix` is a hash. `shell` is the only required key:

| **key**            | **type** | **description**                                                                                   |
| :----------------- | -------- | :------------------------------------------------------------------------------------------------ |
| `shell`            | string   | **required.** the shell command to run                                                            |
| `name`             | string   | label shown in the spinner and summary. Defaults to `shell`.                                      |
| `if`               | string   | only run this command when the given shell command exits 0; otherwise it is reported as `SKIPPED` |
| `env`              | hash     | environment variables prefixed onto `shell` and `if` (e.g. `env: { RAILS_ENV: test }`)            |
| `verbose`          | boolean  | print this command's output while it runs, overriding the global setting in either direction      |
| `only_worktree`    | boolean  | only run this command when in worktree mode                                                       |
| `only_no_worktree` | boolean  | only run this command when not in worktree mode                                                   |

Any other key is ignored, with a warning naming the key and the command.

**`verbose` is only honored in the sequential sections** — `pre_run`, `post_run`, `post_run_success`, and `post_run_failure`. Commands in `parallel_run` all follow the global setting, and `gpush fix` and `gpush run` are always verbose.

Because `changed-files` and `get-specs` exit 1 when nothing matched, they work as an `if:` condition on their own — this skips prettier entirely when no files changed:

```yaml
- name: prettier
  shell: npx prettier --check --ignore-unknown $(gpush changed-files)
  if: gpush changed-files
```

#### Example

```yaml
worktree: true
worktree_copy_gitignored:
  - "config/master.key"
  - ".env"

pre_run:
  - name: npm install
    shell: npm install
    only_worktree: true

parallel_run:
  - name: rspec
    shell: bundle exec rspec
  - name: rubocop
    shell: bundle exec rubocop

post_run_success:
  - name: notify
    shell: echo "All good!"
```

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

### Install gpush using Homebrew (from your clone)

Clone the repo if you have not already:

```bash
git clone https://github.com/nitidbit/gpush
```

**Current Homebrew** (4.x and later) does **not** accept a bare path like `brew install ./Formula/gpush.rb`. It responds with _“Homebrew requires formulae to be in a tap”_. The supported approach is to **tap this repository** (it already has `Formula/gpush.rb` at the repo root), then install by **tap-qualified name**.

From the **root of your clone**:

```bash
cd /path/to/gpush
brew tap YOURNAME/gpush-local "file://$(pwd)"
brew install YOURNAME/gpush-local/gpush
```

Use any tap prefix that is free on your machine (for example your GitHub username plus `-local`). If you need to redo the tap: `brew untap YOURNAME/gpush-local` first.

Reinstall after formula changes:

```bash
brew reinstall YOURNAME/gpush-local/gpush
```

Homebrew keeps its own checkout of the tap; if edits to `Formula/gpush.rb` in your working tree are not picked up, `brew untap …` and `brew tap …` again, or follow your usual flow to refresh that tap clone.

**Without Homebrew:** run the CLI with Ruby from the repo, e.g. `ruby src/ruby/gpush.rb --help` or `ruby src/ruby/gpush.rb --dry-run`.

More on taps: [Taps (Third-Party Repositories)](https://docs.brew.sh/Taps), `man brew tap`.

### Development

Clone the repo, then run the dev-install script to symlink the dev binaries into your PATH:

```bash
scripts/dev-install
```

This links `gpush` (plus the deprecated `gpush_get_specs` and `gpush_changed_files` aliases) from the repo's `bin/` directory into `/opt/homebrew/bin/`. Changes to `src/ruby/` are picked up immediately — no reinstall needed.

To revert:

```bash
scripts/dev-uninstall
```

Edit the files in `src/ruby/`. To test your changes:

```bash
bundle exec rspec        # run the test suite
gpush --dry-run          # smoke test the CLI
```

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
