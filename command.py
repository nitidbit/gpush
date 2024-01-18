import subprocess
import os

def check_allowed_keys(allowed, dictionary):
    actual_keys = dictionary.keys()
    bad_keys = set(actual_keys) - set(allowed)
    if bad_keys:
        raise RuntimeError(f'Problem with command.  {repr(dictionary)} has these unknown keys: {", ".join(bad_keys)}. Allowed keys for a command are: {", ".join(allowed_keys)}')


def check_type(line_intro, value, expected_type, explanation):
    if not isinstance(value, expected_type):
        raise RuntimeError(f'Problem with {line_intro}.  {repr(value)} needs to be of type {repr(expected_type)}.  {explanation}')

class Command:
    allowed_keys = ['shell', 'env', 'if']

    def __init__(self, cmd_dict):
        check_type('Command', cmd_dict, dict, 'Commands need to be a hash with at least a "shell:" line.')
        check_allowed_keys(Command.allowed_keys, cmd_dict)
        self.dict = cmd_dict

    def run(self):
        if 'shell' not in self.dict:
            raise RuntimeError(f'Hi! you need to have a field "shell" in your command: {repr(self.dict)}')

        if 'if' in self.dict:
            ifcommand = self.dict['if']
            check_type('"if" clause', ifcommand, str, 'If you have an "if:" clause, it must have a string which will be run in the shell.')
            result = subprocess.run(ifcommand, shell=True)
            if result.returncode != 0:
                print(f'We are skipping {repr(self.dict["shell"])} because if clause returned {result.returncode}. Expected 0.')
                return

        env = None
        if 'env' in self.dict:
            env = self.dict['env']
            check_type('"env" clause', env, dict, 'An optional "env:" section must have a hash of variable names and values.')
            env = dict(**env, **os.environ)

        shell = self.dict['shell']
        print('\ngpush:', shell)

        subprocess.run(shell, shell=True, env=env)

def run(list_of_commands):
    for cmd_dict in list_of_commands:
        return Command(cmd_dict).run()

