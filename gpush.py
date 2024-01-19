#!/usr/bin/env python3

# import libraries in alphabetic order
import argparse
import command
import os
import subprocess
import yaml
import concurrent.futures
from constants import GpushError, RED, RESET


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

def _run_in_parallel(commands):
    post_processing_tasks = {}
    processes = {}

    with concurrent.futures.ThreadPoolExecutor() as executor:
        futures = [executor.submit(command.run_one, item) for item in commands]

        for future in concurrent.futures.as_completed(futures):
            completed_process = future.result()
            print("  exit code:", completed_process.returncode)

    # try:
    #     while True:
    #         _print_status(processes)
    #         active_process_count = len([name for name, proc in processes.items() if proc.poll() is None])

    #         if active_process_count == 0:
    #             errors = {name: proc.poll() for name, proc in processes.items()
    #                       if proc.poll() is not None and proc.poll() != 0}
    #             return errors

    #         time.sleep(5)
    # except KeyboardInterrupt:
    #     print('KeyboardInterrupt...')
    #     return {"kbdint": 1}
    # finally:
    #     for name, proc in processes.items():
    #         status = proc.poll()
    #         if status is None:
    #             print('Terminating:', name)
    #             proc.terminate()

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
           print(f"Local branch is up to date with the remote branch '{remote_branch}'.")
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


def go():
    remote_branch = get_remote_branch_name()
    setup_remote_branch = check_remote_branch(remote_branch)

    yml = find_and_parse_config()

    command.run(yml['pre_run'])
    print("yml parallel commands", yml['parallel_commands'])
    _run_in_parallel(yml['parallel_commands'])
    command.run(yml['post_run'])


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
    parser.add_argument('--root-dir', dest='root_dir',
                        help="Specify a root directory. Defaults to ./ (current directory)")
    parser.add_argument('-v', '--verbose', dest='output_level', action='store_const', const=1, default=1,
                        help='Verbose output')
    parser.add_argument('-q', '--quiet', dest='output_level', action='store_const', const=0,
                        help='Silence all output')
    parser.add_argument('-d', '--desktop', dest='enable_desktop_notifiction', action='store_true',
                        help='Turn on desktop notifications for this run')
    parser.add_argument('-s', '--save-to', dest='save_file',
                        help='Save output to a file')
    parser.add_argument('-c', '--concurency', dest='concurrency_limit', type=int,
                        help='Specify the max number of concurrent commands')
    return parser


if __name__ == '__main__':
    try:
        args = cli_arg_parser({}).parse_args()

        # print(args)

        go()
    except GpushError as exc:
        print(f'{RED}gpush: Stopping: {exc}{RESET}')
