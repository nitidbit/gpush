#!/usr/bin/env python3
import yaml
import command

def find_and_parse_config():
    with open('gpushrc_default.yml') as f:
        config = yaml.safe_load(f)

    with open('gpushrc.yml') as f:
        user_config = yaml.safe_load(f)
        config.update(user_config)

    print('!!! find_and_parse_config() config=', repr(config))
    return config



if __name__ == '__main__':
    yml = find_and_parse_config()

    root_dir = yml

    command.run(yml['pre_run'])
    command.run(yml['post_run'])


