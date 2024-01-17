import subprocess
import os

def check_type(line_intro, value, expected_type, explanation):
    if not isinstance(value, expected_type):
        raise RuntimeError(f'Problem with {line_intro}.  {repr(value)} needs to be of type {repr(expected_type)}.  {explanation}')

def run(list_of_commands):
    for cmd in list_of_commands:
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
