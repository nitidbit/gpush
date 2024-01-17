import subprocess
import os

def run(list_of_commands):
    for cmd in list_of_commands:
        if not isinstance(cmd, dict):
            raise RuntimeError(f'Hi! your command needs to be hash, but it was: {repr(cmd)}')

        if 'shell' not in cmd:
            raise RuntimeError(f'Hi! you need to have a field "shell" in your command: {repr(cmd)}')

        env = None
        if 'env' in cmd:
            env = cmd['env']
            if not isinstance(env, dict):
                raise RuntimeError(f'Hi! your enviroment variables need to be a dictionary, but instead we found: {repr(env)}')
            env = dict(**env, **os.environ)

        shell = cmd['shell']
        print('\ngpush:', shell)

        subprocess.run(shell, shell=True, env=env)
