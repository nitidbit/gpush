#!/usr/bin/env python3

import argparse
import os
import sys
from os.path import join, dirname, splitext, basename
import gpush_core # noqa (suppress PEP8 import warning)

HERE = dirname(__file__)

# CONFIG FILE? + spec_ignore_dirs, STOPWORDS
TYPE_TO_FILEEND = {
  'spec': '_spec.rb',
  'jest': '.test.jsx' # TODO change
}

def get_all_test_files(spec_dir, type, keywords, spec_ignore_dirs = {}):
  #get spec files/dirs (expand to match whatevs?)
  if type == 'spec':
    test_dir = find_dir(base_dir, 'spec')
  else:
    test_dir = base_dir

  print('looking for test files in {}...'.format(test_dir))
  specs = set()
  for base, dirs, files in os.walk(spec_dir):
      if base in spec_ignore_dirs:
          continue

      for filename in files:
          if not filename.endswith(TYPE_TO_FILEEND[type]):
              continue

          potential_spec = join(base, filename)
          specs.add(potential_spec)

  def contains_keywords(candidate_filename):
      for keyword in keywords:
          if keyword in candidate_filename:
              return True
      return False

  specs = list(filter(contains_keywords, sorted(specs)))
  return specs


def find_dir(base_dir, name):
  for root, subdirs, files in os.walk(base_dir):
    if root.split('/')[-1] == name:
      return root
    for subdir in subdirs:
      if name == subdir:
        return join(root, subdir)
  raise Exception("folder {} not found in {}".format(name, base_dir))


def _parse_cmd_args():
  parser = argparse.ArgumentParser(description='what type of tests')
  parser.add_argument('filename', nargs="?", default=HERE)
  # choices come from config?
  parser.add_argument('-T', '--type', default='spec', choices=['spec', 'jest'])

  args = parser.parse_args()
  return args


if __name__ == '__main__':
  args = _parse_cmd_args()
  base_dir = os.path.realpath(args.filename)

  print('git fetching in {}...'.format(base_dir))
  gpush_core.run("git fetch", cwd=base_dir)

  # get list of changed files
  changed_filenames = gpush_core._get_changed_files(base_dir)
  partial_filenames = [splitext(basename(filepath))[0] for filepath in changed_filenames]
  print('These files have been changed from github: {}'.format(', '.join(partial_filenames)))

  # keywords
  keywords = gpush_core._searchable_strings(partial_filenames, set())
  print ('Keywords: {}'.format(keywords))

  test_files = get_all_test_files(base_dir, args.type, keywords)

  print('changed files: ')
  print(' '.join(test_files))
