"""
  Core logic for gpush that is shared between repos. I.e. this file should be copied as-is from repo to
  repo. Repo specific configuration should be in <repo-root>/gpush.py
"""

from __future__ import print_function

import argparse
import functools
import json
import os
import os.path
import stat
import subprocess
import time
from os.path import join, splitext, basename
from shutil import which

# Ansi escape codes
RED = "\033[31m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
RESET = "\033[0m"

FILENAME_STOP_MIN_LENGTH = 4
CMD_FILES_CHANGED_SINCE_PUSH = "git diff --name-only {} {}"

SOFT_LIMIT_BUFFER = 3


# Run a shell command, returning the 'stdout' output of that command as a string.
def run(command):
    result = subprocess.check_output([command], stderr=subprocess.STDOUT, shell=True)
    return result


# Run a bunch of commands (e.g. 'npm test', 'rubocop') in parallel, printing their status every 5 seconds
def run_in_parallel(commands):
    post_processing_tasks = {}
    processes = {}

    for name, kwargs in commands.items():
        post_task = kwargs.pop('post_task', None)

        if post_task:
            post_processing_tasks[name] = post_task

        processes[name] = subprocess.Popen(**kwargs)

    try:
        while True:
            _print_status(processes)
            active_process_count = len([name for name, proc in processes.items() if proc.poll() is None])

            if active_process_count == 0:
                errors = {name: proc.poll() for name, proc in processes.items()
                          if proc.poll() is not None and proc.poll() != 0}
                return errors

            time.sleep(5)
    except KeyboardInterrupt:
        print('KeyboardInterrupt...')
        return {"kbdint": 1}
    finally:
        for name, proc in processes.items():
            status = proc.poll()
            if status is None:
                print('Terminating:', name)
                proc.terminate()
            elif status == 0:
                if name in post_processing_tasks:
                    print("== Running post process for {} ==".format(name))
                    post_processing_tasks[name]()


def cli_arg_parser(commands):
    list_of_commands = "".join(("\n    {:25} - {}".format(key, ' '.join(val["args"])) for key, val in commands.items()))
    description = 'Run tests and linters before pushing to github.'
    epilog = 'These are the tests and linters that will be run:' + list_of_commands + '\n    rspec'

    parser = argparse.ArgumentParser(
        description=description,
        epilog=epilog,
        formatter_class=argparse.RawDescriptionHelpFormatter)

    parser.add_argument('--dry-run', dest='is_dry_run', action='store_true',
                        help="Don't actually push to github at the end--just run the tests.")
    parser.add_argument('--compare', '-c', dest='compare_branch',
                        help="specify which branch to compare against if don't want the upstream default, example after rebasing")
    return parser


#   Picking Subset of files for Stylelint

def scss_lint_for_changed_files(git_repo_root_dir, compare_branch=None):
    result = {}
    changed_filenames = _get_changed_files(git_repo_root_dir, no_deletes=True, compare_branch=compare_branch)
    changed_scss_files = [fn for fn in changed_filenames if fn.endswith('css')]

    command = ['npx', 'stylelint']
    command.extend(changed_scss_files)

    if changed_scss_files:
        result["stylelint"] = {
            'args': command
        }

    return result


def eslint_for_changed_files(git_repo_root_dir, compare_branch=None):
    result = {}
    changed_filenames = _get_changed_files(git_repo_root_dir, no_deletes=True, compare_branch=compare_branch)
    changed_js_files = [fn for fn in changed_filenames if (fn.endswith('js') or fn.endswith('jsx'))]

    command = ['npx', 'eslint']
    command.extend(changed_js_files)

    if changed_js_files:
        result["eslint"] = {
            'args': command
        }

    return result


def prettier_for_changed_files(git_repo_root_dir, compare_branch=None):
    result = {}
    changed_filenames = _get_changed_files(git_repo_root_dir, no_deletes=True, compare_branch=compare_branch)
    # changed_prettier_files = [fn for fn in changed_filenames if (fn.endswith(tuple(prettier_extensions)))]

    command = ['npx', 'prettier', '--check', '--plugin=@prettier/plugin-ruby']
    command.extend(changed_filenames)

    if changed_filenames:
        result["prettier"] = {
            'args': command
        }

    return result

def rubocop_for_changed_files(git_repo_root_dir, compare_branch=None):
    result = {}
    changed_filenames = _get_changed_files(git_repo_root_dir, no_deletes=True, compare_branch=compare_branch)
    # changed_prettier_files = [fn for fn in changed_filenames if (fn.endswith(tuple(prettier_extensions)))]

    command = ['bundle', 'exec', 'rubocop', '--force-exclusion', '--only-recognized-file-types']
    command.extend(changed_filenames)

    if changed_filenames:
        result["rubocop"] = {
            'args': command
        }

    return result

def jest_soft_limit_warning(git_repo_root_dir):
    # read package json hard limits
    with open(join(git_repo_root_dir, 'package.json'), 'r') as f:
        package_json = json.load(f)

    global_hard_limits = package_json['jest']['coverageThreshold']['global']
    soft_limits = {key: value + SOFT_LIMIT_BUFFER for key, value in global_hard_limits.items()}

    # read jest_test_coverage for actual numbers
    with open(join('jest_test_coverage.txt'), 'r') as f:
        f_lines = f.readlines()

    clean_f_line = f_lines[3].replace('[32;1m', '').replace('[0m', '').replace('[31;1m', '').replace('\x1b', '')
    stmts, branches, funcs, lines = [float(value) for value in clean_f_line.split("|")[1:5]]

    # do math
    if stmts < soft_limits['statements']:
        print("  {}Test coverage for statements {} is below soft limit {}{}".format(YELLOW, stmts,
                                                                                    soft_limits['statements'], RESET))

    if branches < soft_limits['branches']:
        print("  {}Test coverage for branches {} is below soft limit {}{}".format(YELLOW, branches,
                                                                                  soft_limits['branches'], RESET))

    if funcs < soft_limits['functions']:
        print("  {}Test coverage for functions {} is below soft limit {}{}".format(YELLOW, funcs,
                                                                                   soft_limits['functions'], RESET))

    if lines < soft_limits['lines']:
        print("  {}Test coverage for lines {} is below soft limit {}{}".format(YELLOW, lines, soft_limits['lines'],
                                                                               RESET))


#
#   Picking Subset of files for RSPEC
#

# Returns a dictionary like COMMANDS which will run rspec for a subset of our specs.
def rspec_for_changed_files(
        git_repo_root_dir,  # project root directory which should be the same as the git root, e.g. "./"
        rspec_root_dir,  # directory in which to run `rspec`. E.g. 'navigate' or 'bedsider-web/bedsider'
        filename_stop_words,  # e.g. set(['for', 'csv', 'spec', 'job', 'controller', 'admin', 'helper', '']),
        spec_ignore_dirs,
        compare_branch=None
):
    result = {}

    changed_filenames = _get_changed_files(git_repo_root_dir, compare_branch=compare_branch)
    partial_filenames = [splitext(basename(filepath))[0] for filepath in changed_filenames]
    #  print 'These files have been changed from github: {}'.format(', '.join(partial_filenames))

    keywords = _searchable_strings(partial_filenames, filename_stop_words)
    print('Searching for specs with keywords derived from changed files:\n    {}'.format(', '.join(keywords)))

    spec_dir = join(rspec_root_dir, 'spec')
    specs = _get_specs(spec_dir, keywords, spec_ignore_dirs)
    print("These Spec files look similar to your changed files:")
    print("\n".join(("    {}".format(fname) for fname in specs)))

    # return a "command" to run those specs
    if specs:
        result["rspec"] = {
            'cwd': rspec_root_dir,
            'args': ['bundle', 'exec', 'rspec'] + list(specs)}
    return result


# gpush.py client code should call this once files have been fetched and after import, like this:
#   import gpush_core
#   gpush_core.after_downloads()
# TODO: automate running this after all downloads (which will become a config step)
def after_downloads():
    # make lint.py executable by all
    lint_path = "./lint.py"
    if os.path.isfile(lint_path):
        lint_stat = os.stat(lint_path)
        os.chmod(lint_path, lint_stat.st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


# Print all the commands running and if they have finished or not
def _print_status(processes):
    print()
    for key, proc in processes.items():
        status = proc.poll()
        if status is None:
            s = 'working...'
        elif status == 0:
            s = '{}OK{}'.format(GREEN, RESET)
        else:
            s = '{}EXIT CODE {}{}'.format(RED, status, RESET)

        print('  {key:25} - {s}'.format(key=key, s=s))
    print()


# Given a bunch of filenames like 'clinics_show.haml', return the interesting words like ['clinics', 'show']
def _searchable_strings(filenames, filename_stop_words):
    result = set()
    for filename in filenames:
        result.update(filename.split('_'))
    result = result - filename_stop_words
    result = list(filter(lambda word: len(word) >= FILENAME_STOP_MIN_LENGTH, result))
    return result


# Return list of files that have changed since 'origin/BRANCH'
# e.g. ['/Users/winstonw/bedsider-web/bedsider/app/models/clinic.rb', ...]
@functools.cache
def _get_changed_files(git_repo_root_dir, no_deletes=False, compare_branch=None):
    git_result = run("git rev-parse --abbrev-ref HEAD").decode()
    local_branch = git_result.strip()
    compare_branch = compare_branch or "origin/{}".format(local_branch)

    try:
        cmd = CMD_FILES_CHANGED_SINCE_PUSH.format(compare_branch, local_branch)
        output = run(cmd)

    except subprocess.CalledProcessError:
        # Assuming error: when we are on a local branch, diffing with origin/$BRANCH fails
        default = 'main'
        prompt = '''
Could not `git diff` against {}. What branch should I diff against to determine what you are going to
push? [{}] '''.format(compare_branch, default)
        origin_branch = input(prompt).strip() or default

        cmd = CMD_FILES_CHANGED_SINCE_PUSH.format(origin_branch, local_branch)
        output = run(cmd)
    output = output.decode()
    files = filter(lambda fn: fn, output.split("\n"))  # filter out emtpy lines

    files = [os.path.realpath(os.path.join(git_repo_root_dir, fn)) for fn in files]

    if no_deletes:  # filter out deleted files
        files = [fn for fn in files if (os.path.exists(fn))]

    return files


# Return list of existing spec files, e.g. ['specs/api/cinics_spec.rb']
def _get_specs(spec_dir, keywords, spec_ignore_dirs):
    specs = set()

    # find all spec files
    for base, dirs, files in os.walk(spec_dir):
        if base in spec_ignore_dirs:
            continue

        for filename in files:
            if not filename.endswith('_spec.rb'):
                continue

            potential_spec = join(base, filename)
            specs.add(potential_spec)

    # choose only files with our keywords
    def contains_keywords(candidate_filename):
        for keyword in keywords:
            if keyword in candidate_filename:
                return True
        return False

    specs = list(filter(contains_keywords, sorted(specs)))

    return specs


# Max OSX native notifications of build status.
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
def notify(success=True, msg="Finished!"):
    afplay = which('afplay')
    if afplay is not None:
        if "GPUSH_SOUND_SUCCESS" in os.environ and os.path.isfile(os.environ["GPUSH_SOUND_SUCCESS"]) and success:
            subprocess.Popen([afplay, os.environ["GPUSH_SOUND_SUCCESS"]])

        if "GPUSH_SOUND_FAIL" in os.environ and os.path.isfile(os.environ["GPUSH_SOUND_FAIL"]) and not success:
            subprocess.Popen([afplay, os.environ["GPUSH_SOUND_FAIL"]])

    terminal_notifier = which('terminal-notifier')
    if terminal_notifier is None or "GPUSH_NO_NOTIFIER" in os.environ:
        return

    subtitle = "Success" if success else "Fail"
    sound = "Hero" if success else "Basso"
    emojis = "🥳🎉🍾" if success else "🤨💩🙈"
    subprocess.run([terminal_notifier,
                    '-title', 'GPush Build',
                    '-subtitle', f'{emojis} {subtitle} {emojis}',
                    '-message', f'{msg}',
                    '-sound', sound,
                    # for the icon... (should be able to specify a file but that doesn't seem to work)
                    '-sender', 'com.apple.terminal',
                    ])
