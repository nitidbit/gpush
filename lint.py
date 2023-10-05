#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Rewrite files with linters: ESLint, Prettier, and Rubocop. Only affects files that you
have changed since you last pushed to git.
"""

import subprocess
import os
from os.path import join, dirname

PROJECT_ROOT_DIR = dirname(__file__)
ESLINT_FILE_EXTENSIONS = ['.js', '.jsx', '.ts', '.tsx', '.mjs', '.cjs']

def run(command):
    result = subprocess.check_output([command], stderr=subprocess.STDOUT, shell=True)
    return result

def get_changed_files(git_repo_root_dir, no_deletes = True):
    CMD_FILES_CHANGED = "git diff --name-only {}"

    try:
        cmd = CMD_FILES_CHANGED.format("@{upstream}")
        output = run(cmd)

    except subprocess.CalledProcessError:
        # Assuming that error: when we are on a local branch, diffing with origin/$BRANCH fails
        DEFAULT = 'origin/main'
        prompt = '''
Could not `git diff` against origin. What branch should I diff against? [{}] '''.format(DEFAULT)
        origin_branch = input(prompt).strip() or DEFAULT

        cmd = CMD_FILES_CHANGED.format(origin_branch)
        output = run(cmd)

    output = output.decode()
    files = filter(lambda fn: fn, output.split("\n"))  # filter out emtpy lines
    files = [os.path.realpath(os.path.join(git_repo_root_dir, fn)) for fn in files]

    if no_deletes: # filter out deleted files
        files = [fn for fn in files if (os.path.exists(fn))]

    return files


if __name__ == '__main__':
    changed_filenames = get_changed_files(PROJECT_ROOT_DIR)
    eslint_files = [fn for fn in changed_filenames if fn.endswith(tuple(ESLINT_FILE_EXTENSIONS))]

    prettier_command = ['npx', 'prettier', '--write', '--plugin=@prettier/plugin-ruby'] + changed_filenames

    subprocess.run(prettier_command)
    subprocess.run(['npx', 'eslint', '--fix'] + eslint_files)
    subprocess.run([
        'bundle',
        'exec',
        'rubocop',
        '--force-exclusion',
        '--autocorrect-all',
        '--only-recognized-file-types'
        ] + changed_filenames)
    subprocess.run(prettier_command)

    print("Done Linting")
