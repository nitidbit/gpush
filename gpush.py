#!/usr/bin/env python3
import os

import yaml
import command
import subprocess

def find_and_parse_config():
    with open('gpushrc.yml') as f:
        config = yaml.safe_load(f)

    merge_imports(config)

    print('!!! find_and_parse_config() config=', repr(config))
    return config

# import other config files, we expect a single path or a list of paths
def merge_imports(config):
    # default to empty list if no import is specified
    config['import'] = config.get('import', [])
    # allow a single import to be specified as a string
    if not isinstance(config['import'], (list, tuple)):
        config['import'] = [config['import']]
    for file in config['import']:
        if os.path.exists(file) and os.path.isfile(file):
            with open(file) as f:
                config.update(yaml.safe_load(f))
        else:
            print(f"import file '{file}' does not exist or is not a file, ignoring")

def get_remote_branch_name():
    try:
        branch_name = subprocess.check_output(['git', 'rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}'], stderr=subprocess.DEVNULL, text=True).strip()
        return branch_name
    except subprocess.CalledProcessError:
        return None # Return None if no remote branch is set

def is_git_up_to_date_with_remote_branch():
    try:
        subprocess.check_call(['git', 'fetch'])
        print("")
        try:
            subprocess.check_call(['git', 'rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}'])
        except subprocess.CalledProcessError:
            return False  # No upstream branch is set

        # Get the common ancestor (merge base) of the local and remote branches
        merge_base = subprocess.check_output(['git', 'merge-base', '@', '@{u}'], text=True).strip()
        remote_commit = subprocess.check_output(['git', 'rev-parse', '@{u}'], text=True).strip()

        # If the merge base is the same as the remote commit, local is up to date or ahead
        return merge_base == remote_commit
    except subprocess.CalledProcessError:
        return False  # Return False in case of an error

def go():
    remote_branch = get_remote_branch_name()
    if remote_branch:
        if is_git_up_to_date_with_remote_branch():
            print(f"Local branch is up to date with the remote branch '{remote_branch}'.")
            # Continue with your operations below
        else:
            print(f"Local branch is not up to date with the remote branch '{remote_branch}'. Exiting.")
            return  # Stop further execution
    else:
        user_input = input("No remote branch set. Would you like to set up a remote branch? (y/n): ")
        if user_input.lower() == 'y':
            setup_remote_branch = True
            # Later use this flag to set up the remote branch
        else:
            print("No remote branch setup. Exiting.")
            return  # Stop further execution

    yml = find_and_parse_config()

    root_dir = yml

    command.run(yml['pre_run'])
    command.run(yml['post_run'])

if __name__ == '__main__':
    go()
