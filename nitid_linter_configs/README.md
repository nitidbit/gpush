These files are Nitid's standard linter configuration files. They are shared between a bunch of
projects, so any change here propagates everywhere.

## RuboCop — `rubocop_shared.yml`

RuboCop can inherit a config over HTTP, so there's nothing to download in `pre_run`. Point your
project's `.rubocop.yml` at the raw URL:

```yaml
# .rubocop.yml
inherit_from:
  - https://raw.githubusercontent.com/nitidbit/gpush/main/nitid_linter_configs/rubocop_shared.yml
  - .rubocop_todo.yml

AllCops:
  TargetRubyVersion: 3.3
```

Anything you add below `inherit_from` overrides the shared file, so a project can disagree with the
standard without forking it.

Four things to know:

- **Set your own `TargetRubyVersion`.** The shared file deliberately doesn't.
- **Your `.rubocop_todo.yml` goes in your `inherit_from` list**, not in the shared file. A remote
  config can only inherit other remote configs.
- **Arrays are replaced, not merged.** If you set your own `AllCops/Exclude` you'll wipe the shared
  one unless you ask for a merge:

  ```yaml
  inherit_mode:
    merge:
      - Exclude
  ```

- **Add `.rubocop-https-*` to your `.gitignore`.** RuboCop caches the download as a file in your
  project root, named `.rubocop-` plus the URL with every non-alphanumeric character turned into a
  dash — so this config lands as `.rubocop-https---raw-githubusercontent-com-nitidbit-gpush-main-nitid-linter-configs-rubocop-shared-yml`.

Requires rubocop >= 1.72 (for the `plugins` key), plus `rubocop-rails`, `rubocop-rspec`, and
`rubocop-rails-accessibility` in your Gemfile.

The `@prettier/plugin-ruby` cop settings are inlined into `rubocop_shared.yml`. A remotely-inherited
config can't reach `node_modules/`, so don't add that `inherit_from` line yourself — you'd only
re-disable the trailing-comma cops the shared file turns back on.

## The other configs

The rest are still fetched by curl in `pre_run`, which overwrites the local copy:

```yaml
# gpushrc.yml
pre_run:
  - shell: curl 'https://raw.githubusercontent.com/nitidbit/gpush/main/nitid_linter_configs/.prettierrc.json' -O
  - shell: curl 'https://raw.githubusercontent.com/nitidbit/gpush/main/nitid_linter_configs/.stylelintrc.js' -O
  - shell: curl 'https://raw.githubusercontent.com/nitidbit/gpush/main/nitid_linter_configs/.eslintrc_typescript.json' -o '.eslintrc.json'
```

`.rubocop.yml` in this folder is the older download-and-replace version of the RuboCop config, kept
for projects that haven't switched to `rubocop_shared.yml` yet.
