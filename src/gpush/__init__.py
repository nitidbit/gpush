"""
gPush, a tool for running tests, linters, etc before `git push`ing.
"""

# import libraries in alphabetic order
import argparse
import os
import subprocess
import yaml
import concurrent.futures
import time
from pathlib import Path

from .constants import GpushError, GREEN, RED, RESET
from . import commands
from .commands import Command, Status
from .gpush_core import notify

def find_and_parse_config():
    LIB_DIR = Path(__file__).parent

    locations_to_try = [
        './gpushrc.yaml',
        './gpushrc.yml',
        LIB_DIR / 'gpushrc_default.yaml',
    ]

    for rc_path in locations_to_try:
        if Path(rc_path).exists():
            break

    print('gpush: using config file:', rc_path)

    with open(rc_path) as f:
        config = yaml.safe_load(f)

    merge_imports(config)

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
            print(f"gpush: import file '{file}' does not exist or is not a file, ignoring")

# Print all the commands running and if they have finished or not
def _print_status(commands_and_futures):
    print()
    num_running = 0
    for command, future in commands_and_futures:
        if future.running():
            #  status_str = 'working...'
            num_running += 1
        elif future.exception():
            print(f'gpush:  ERROR in {repr(command.name())}: {future.exception()}')

        status = command.status
        if status == Status.SUCCESS:
            status_str = '{}OK{}'.format(GREEN, RESET)
        elif status == Status.FAIL:
            exitcode = command.run_completed_process.returncode
            status_str = '{}EXIT CODE {}{}'.format(RED, exitcode, RESET)
        else:
            status_str = status

        print(f'  {command.name():25} - {status_str}')
    print()
    return num_running

def _run_in_parallel(list_of_command_dicts):
    '''Runs all the commands in parallel. Return number of errors, or 0'''
    STATUS_TIME_SEC = 2

    commands = [Command(cmd_dict) for cmd_dict in list_of_command_dicts]

    with concurrent.futures.ThreadPoolExecutor() as executor:
        commands_and_futures = [[command, executor.submit(command.run)] for command in commands]

        # wait for commands to finish, print a status summary every 5 seconds
        try:
            num_running = _print_status(commands_and_futures)
            while num_running > 0:
                time.sleep(STATUS_TIME_SEC)
                num_running = _print_status(commands_and_futures)

        except KeyboardInterrupt:
            print('gpush: KeyboardInterrupt...')
            return 1 # an error so we abort
        finally:
            pass
            # !!! terminate any commands that might still be running

        errors = [0 if command.status == Status.SUCCESS else 1 for command in commands]
        return sum(errors)

def get_remote_branch_name():
    try:
        branch_name = subprocess.check_output(['git', 'rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}'],
                                              stderr=subprocess.DEVNULL, text=True).strip()
        return branch_name
    except subprocess.CalledProcessError:
        return None  # Return None if no remote branch is set


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

        # If the merge base is the same as the remote commit, local is up-to-date or ahead
        return merge_base == remote_commit
    except subprocess.CalledProcessError:
        return False  # Return False in case of an error

def check_remote_branch(remote_branch):
    '''
    Is the current branch tracking a remote branch? Have we `git fetch`ed lately? If we are not
    tracking a remote branch, should we make a remote branch?
    '''
    setup_remote_branch = False
    if remote_branch:
       if is_git_up_to_date_with_remote_branch():
           print(f"gpush: Local branch is up to date with the remote branch '{remote_branch}'.")
           # Continue with your operations below
       else:
           raise GpushError(f"Local branch is not up to date with the remote branch '{remote_branch}'. Exiting.")
           # Stop further execution
    else:
       user_input = input("No remote branch set. Would you like to set up a remote branch? (y/n): ")
       if user_input.lower() == 'y':
           setup_remote_branch = True
           # Later use this flag to set up the remote branch
       else:
           raise GpushError("No remote branch setup.")
           # Stop further execution

    return setup_remote_branch


def go(args):
    remote_branch = get_remote_branch_name()
    setup_remote_branch = check_remote_branch(remote_branch)

    yml = find_and_parse_config()

    commands.run_all(yml.get('pre_run', []))

    errors = _run_in_parallel(yml.get('parallel_run', []))

    if errors != 0 
        notify(False)
        ABORTED = "《 Errors detected 》 Exiting gpush."
        print(ABORTED)
    elif args.is_dry_run:
        notify(False)
        DRY_RUN = "《 Dry run completed 》 No errors detected."
        print(DRY_RUN)
    else:
        subprocess.run(['git', 'push'])
        commands.run_all(yml.get('post_run', []))
        notify(True)
        DOING_GREAT = "《 🌺 》 Good job! You're doing great."
        print(DOING_GREAT)

def cli_arg_parser(commands):
    list_of_commands = "".join(("\n    {:25} - {}".format(key, ' '.join(val["args"])) for key, val in commands.items()))
    description = 'Run tests and linters before pushing to github.'
    epilog = 'These are the tests and linters that will be run:' + list_of_commands + '\n    rspec'

    parser = argparse.ArgumentParser(
        description=description,
        epilog=epilog,
        formatter_class=argparse.RawDescriptionHelpFormatter)

    parser.add_argument('--dry-run', dest='is_dry_run', action='store_true',
                        help="Don't actually push to github at the end--just run the tests (commands)")
    #  parser.add_argument('--root-dir', dest='root_dir',
    #                      help="Specify a root directory. Defaults to ./ (current directory)")
    #  parser.add_argument('-v', '--verbose', dest='output_level', action='store_const', const=1, default=1,
    #                      help='Verbose output')
    #  parser.add_argument('-q', '--quiet', dest='output_level', action='store_const', const=0,
    #                      help='Silence all output')
    #  parser.add_argument('-d', '--desktop', dest='enable_desktop_notifiction', action='store_true',
    #                      default=True,
    #                      help='Turn on desktop notifications for this run')
    #  parser.add_argument('-s', '--save-to', dest='save_file',
    #                      help='Save output to a file')
    #  parser.add_argument('-c', '--concurency', dest='concurrency_limit', type=int,
    #                      help='Specify the max number of concurrent commands')
    return parser

def start():
    try:
        args = cli_arg_parser({}).parse_args()
        go(args)

    except GpushError as exc:
        print(f'{RED}gpush: Stopping: {exc}{RESET}')
        notify(False)
