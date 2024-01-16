#!/usr/bin/env python3
import yaml
import subprocess

def find_and_parse_config():
    with open('gpushrc.yml') as f:
        data = yaml.safe_load(f)
        print('!!! find_and_parse_config data=', repr(data))
        return data

def run_commands(list_of_commands):
    for cmd in list_of_commands:
        print('\ngpush:', cmd)
        subprocess.run(cmd, shell=True)

if __name__ == '__main__':
    yml = find_and_parse_config()

    run_commands(yml['pre_run'])
    run_commands(yml['post_run'])


