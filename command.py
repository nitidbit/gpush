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

allowed_keys = ['shell', 'env', 'if']
def run(list_of_commands):
    for cmd in list_of_commands:
        check_allowed_keys(allowed_keys, cmd)
        check_type('Command', cmd, dict, 'Commands need to be a hash with at least a "shell:" line.')

        if 'shell' not in cmd:
            raise RuntimeError(f'Hi! you need to have a field "shell" in your command: {repr(cmd)}')

        if 'if' in cmd:
            ifcommand = cmd['if']
            check_type('"if" clause', ifcommand, str, 'If you have an "if:" clause, it must have a string which will be run in the shell.')
            result = subprocess.run(ifcommand, shell=True)
            if result.returncode != 0:
                print(f'We are skipping {repr(cmd["shell"])} because if clause returned {result.returncode}. Expected 0.')
                return

        env = None
        if 'env' in cmd:
            env = cmd['env']
            check_type('"env" clause', env, dict, 'An optional "env:" section must have a hash of variable names and values.')
            env = dict(**env, **os.environ)

        shell = cmd['shell']
        print('\ngpush:', shell)

        subprocess.run(shell, shell=True, env=env)
