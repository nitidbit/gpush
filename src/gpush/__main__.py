import gpush
from gpush.constants import GpushError, GREEN, RED, RESET

if __name__ == '__main__':
    try:
        args = gpush.cli_arg_parser({}).parse_args()
        gpush.go(args)

    except GpushError as exc:
        print(f'{RED}gpush: Stopping: {exc}{RESET}')
        gpush.notify(False)
