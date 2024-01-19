"""
Functions related to parsing and running "Commands"
"""
import subprocess
import os
from constants import GpushError, CYAN, RESET

def check_allowed_keys(allowed, dictionary):
    actual_keys = dictionary.keys()
    bad_keys = set(actual_keys) - set(allowed)
    if bad_keys:
        raise GpushError(f'Problem with command.  {repr(dictionary)} has these unknown keys: {", ".join(bad_keys)}. Allowed keys for a command are: {", ".join(allowed)}')


def check_type(line_intro, value, expected_type, explanation):
    if not isinstance(value, expected_type):
        raise GpushError(f'Problem with {line_intro}.  {repr(value)} needs to be of type {repr(expected_type)}.  {explanation}')

class Command:
    allowed_keys = ['shell', 'env', 'if', 'name']

    def __init__(self, cmd_dict):
        self.dict = cmd_dict
        check_type(f'Command {self.name()}', cmd_dict, dict, 'Commands need to be a hash with at least a "shell:" line.')
        check_allowed_keys(Command.allowed_keys, cmd_dict)

    def name(self):
        if 'name' in self.dict: return self.dict['name']
        if 'shell' in self.dict: return self.dict['shell']
        return repr(self.dict)

    def run(self):
        if 'shell' not in self.dict:
            raise GpushError(f'Hi! you need to have a field "shell" in your command: {repr(self.dict)}')

        if 'if' in self.dict:
            ifcommand = self.dict['if']
            check_type('"if" clause', ifcommand, str, 'If you have an "if:" clause, it must have a string which will be run in the shell.')
            result = subprocess.run(ifcommand, shell=True)
            if result.returncode != 0:
                print(f'We are skipping {self.name()} because if clause returned {result.returncode}. Expected 0.')
                return

        env = None
        if 'env' in self.dict:
            env = self.dict['env']
            check_type('"env" clause', env, dict, 'An optional "env:" section must have a hash of variable names and values.')
            env = dict(**env, **os.environ)

        shell = self.dict['shell']
        print(f'\n{CYAN}gpush run:', self.name(), RESET)

        return subprocess.run(shell, shell=True, env=env)

def run(list_of_commands):
    for cmd_dict in list_of_commands:
        run_one(cmd_dict)

def run_one(cmd_dict):
    cmd = Command(cmd_dict)
    completed_process = cmd.run()
    if completed_process.returncode != 0:
        raise GpushError(f'Command {repr(cmd.name())} exited with code {completed_process.returncode}')
    return completed_process

