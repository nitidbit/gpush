# gPush
=======
> This repo contains files needed for the `gpush` script, which runs tests/linters/etc prior to git push in order to ensure better code

## Developer Setup
==================

### Installation

- **Python**: Python 3 comes by default with MacOS, but you can also get it with Brew: `brew install python`

- **Python packages**: 
  ```
  cd gpush
  pip3 install -r requirements.txt
  ```

### Run
    ./gpush.py

## Important files
==================
### gpush settings
- ``
### linter configurations
- eslint (for JavaScript & TypeScript)
  - `.eslintrc.json`
  - `.eslint_typescript.json`
- rubocop (for Ruby)
  - `.rubocop.yml`
- stylelint (for Scss)
  - `.stylelintrc.js`
  - `.stylelintrc.json`
  - *plugin*: `stylelint_plugin_nitid_use_stylekit.js`

### prettier (code formatter) configuration
- *usage*: JavaScript & TypeScript, Ruby, and potentially Scss
- *note*: for convenience, you can use prettier the following ways:
  - set up "format-on-save" in your IDE.  See [here](https://www.educative.io/answers/how-to-set-up-prettier-and-automatic-formatting-on-vs-code)
  - call`lint.py` (work-in-progress) for autofixes.
- `.prettierrc.json`

## What actually happens during gPush?
================

See below image:

![Flow](https://github.com/nitidbit/gpush/blob/release/v2-hackathon/gpush_diagram.png?raw=true)


