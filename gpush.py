#!/usr/bin/env python3
import yaml
import subprocess

def find_and_parse_config():
    with open('gpushrc_default.yml') as f:
        config = yaml.safe_load(f)

    with open('gpushrc.yml') as f:
        user_config = yaml.safe_load(f)
        config.update(user_config)

    print('!!! find_and_parse_config() config=', repr(config))
    return config

def run_commands(list_of_commands):
    for cmd in list_of_commands:
        print('\ngpush:', cmd)
        subprocess.run(cmd, shell=True)

if __name__ == '__main__':
    yml = find_and_parse_config()

    root_dir = yml

    run_commands(yml['pre_run'])
    run_commands(yml['post_run'])


