These files are Nitid's standard linter configuration files. They are shared between a bunch of
projects. We use them by downloading them at the beginning of the gpush script. That way any changes
are propagated to all projects.

```
# gpushrc.yaml

pre_run:

  # moved to /nitid_linter_configs/ folder
  - shell: curl 'https://raw.githubusercontent.com/nitidbit/gpush/main/nitid_linter_configs/rubocop.yml' -o .rubocop.yml

  # soon to be moved /nitid_linter_configs/ folder
  - shell: curl 'https://raw.githubusercontent.com/nitidbit/gpush/main/.prettierrc.json' -O
  - shell: curl 'https://raw.githubusercontent.com/nitidbit/gpush/main/.stylelintrc.js' -O
  - shell: curl 'https://raw.githubusercontent.com/nitidbit/gpush/main/.eslintrc_typescript.json' -o '.eslintrc.json'
  - shell: curl 'https://raw.githubusercontent.com/nitidbit/gpush/main/lint.py' -O
```

