Gpush
========
This repo contains files needed for the `gpush` script, which runs tests/linters/etc prior to git push in order to ensure better code

## Installation

In your project, please install the following:

### Gemfile
Rubocop - most likely, it is already installed automatically in a Rails codebase

### Package.json
Eslint - most likely, it is already installed automatically in a React codebase

```
"devDependencies": {
  "eslint-config-airbnb": "^19",
  "eslint-config-prettier": "^8",
  "prettier": "^2"
  "stylelint": "^14",
  "stylelint-config-prettier": "^9",
  "stylelint-config-standard": "^29",
  "stylelint-prettier": "^2"
}
```

## Prettier formatting on save

It saves developers a lot of time to activate prettier's "format on save" option in your IDE.
How this is done is different from each IDE.  For VScode, refer to [this](https://scottsauber.com/2017/06/10/prettier-format-on-save-never-worry-about-formatting-javascript-again/)