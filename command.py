import subprocess
def run(list_of_commands):
    for cmd in list_of_commands:
        if not isinstance(cmd, dict):
            raise RuntimeError(f'Hi! your command needs to be hash, but it was: {repr(cmd)}')

        if 'shell' not in cmd:
            raise RuntimeError(f'Hi! you need to have a field "shell" in your command: {repr(cmd)}')

        shell = cmd['shell']
        print('\ngpush:', shell)

        subprocess.run(shell, shell=True)
