Gpush
========
This repo contains files needed for the `gpush` script, which runs tests/linters/etc prior to git push in order to ensure better code

## Installation

In your project, please install the following:

### Gemfile
Rubocop - most likely, it is already installed automatically in a Rails codebase
For "@prettier/plugin-ruby", need to add the following gems:
```
  gem 'prettier_print'
  gem 'syntax_tree'
  gem 'syntax_tree-haml'
  gem 'syntax_tree-rbs'
```

### Package.json
Eslint - most likely, it is already installed automatically in a React codebase

```
"devDependencies": {
  "eslint-config-airbnb": "^19",
  "eslint-config-prettier": "^8",
  "postcss-scss": "^4",
  "prettier": "^2"
  "stylelint": "^14",
  "stylelint-config-prettier": "^9",
  "stylelint-config-standard": "^29",
  "stylelint-prettier": "^2"
}
```
Prettier - to run prettier on ruby files:
```
"devDependencies": {
  "@prettier/plugin-ruby": "^4,
}
```
Note: if running in cmd line, `npx prettier -w` does not automatically include ruby files, have to `npx prettier -w --plugin=@prettier/plugin-ruby` # add to prettierrc.json once file expansion regression addressed

## Prettier formatting on save

It saves developers a lot of time to activate prettier's "format on save" option in your IDE.
How this is done is different from each IDE.  For VScode, refer to [this](https://scottsauber.com/2017/06/10/prettier-format-on-save-never-worry-about-formatting-javascript-again/)
