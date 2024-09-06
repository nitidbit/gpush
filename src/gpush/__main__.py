import argparse
from . import start
from .__version__ import __version__

def main():
    # Create an ArgumentParser object
    parser = argparse.ArgumentParser(description="gpush: Utilities for running linters and tests locally before pushing to a remote git repository")

    # Add a --version flag
    parser.add_argument('--version', action='version', version=f'%(prog)s {__version__}')

    # Pass remaining args to start()
    args, unknown_args = parser.parse_known_args()

    # Call the existing start function with the remaining arguments
    start(unknown_args)

if __name__ == '__main__':
    main()
