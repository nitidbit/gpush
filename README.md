# gPush

This repo contains files needed for the `gpush` script, which runs tests/linters/etc prior to git push in order to ensure better code

## User Setup

### Install gpush using homebrew

clone the gpush repo (if you have not yet done so)

```
git clone https://github.com/nitidbit/gpush
```

Install (use `brew reinstall` to update to a new version)

```
brew install [path-to-local-gpush-repo]/Formula/gpush.rb
```

## Developer Setup

[Here are the stories/tickets we are working on:](https://github.com/orgs/nitidbit/projects/3)

### Run

run the command `gpush`

### gpush settings `gpushrc.yml`

| **config key**      | **type**           | **values**                              |
| :------------------ | ------------------ | :-------------------------------------- |
| root_dir            | string             | path to working directory               |
| pre_run             | string or [string] |                                         |
| post_run            | string or [string] |                                         |
| import              | string or [string] | array of file paths or single file path |
| shell               | string             | shell commands to execute               |
| <NAME>              | string             | sets environment <NAME> to string       |
| if                  | string             | conditional shell expression            |
| command_definitions | object             | definition of a command                 |

### linter configurations

- eslint (for JavaScript & TypeScript)
  - `.eslintrc.json`
  - `.eslint_typescript.json`
- rubocop (for Ruby)
  - `.rubocop.yml`
- stylelint (for Scss)
  - `.stylelintrc.js`
  - `.stylelintrc.json`
  - _plugin_: `stylelint_plugin_nitid_use_stylekit.js`

### prettier (code formatter) configuration

- _usage_: JavaScript & TypeScript, Ruby, and potentially Scss
- _note_: for convenience, you can use prettier the following ways:
  - set up "format-on-save" in your IDE. See [here](https://www.educative.io/answers/how-to-set-up-prettier-and-automatic-formatting-on-vs-code)
  - call`lint.py` (work-in-progress) for autofixes.
- `.prettierrc.json`

## What actually happens during gPush?

See below image:
![Flow](https://github.com/nitidbit/gpush/blob/release/v2-hackathon/gpush_diagram.png?raw=true)

## How to Create a New Release Version

### Step 1: Prepare Your Repository

1. Commit Your Changes: Ensure all necessary changes are committed to your Git repository. Homebrew will pull exactly what's in the repository at the time of archiving.
2. Tag Your Release: If you haven't already, tag the commit that you want to package. Tags help in versioning and maintaining stable releases. Use semantic versioning for clarity. For example:

```
git tag -a v1.0.0 -m "Release version 1.0.0"
git push origin v1.0.0
```

### Step 2: Publish the release

- Go to your GitHub repository page.
- Click on "Releases" or "Tags".
- Find the tag you created (v1.0.0 in this example).
- Click "Edit tag" or "Draft a new release".

### Step 3: Update Your Homebrew Formula - IN THE OTHER GIT REPO: homebrew-gpush

1. Get the url for the tarball. It will be something like https://github.com/username/reponame/releases/download/v1.0.0/gpush-1.0.0.tar.gz.
2. Download the tarball. Use the following command to get the checksum (replace with the correct filename)
   ```
   shasum -a 256 ~/Downloads/gpush-1.0.0.tar.gz
   ```
3. Update Formula/gpush.rb in the homebrew-gpush repo

   - Update the url Field: set the url field to the direct download URL of your tarball.
   - Update the sha256 Field

4. (Optional) save the previous `gpush.rb` formula file as the old version number, eg `gpush@0.0.1.rb`
5. Test the Formula locally to ensure it downloads and installs correctly.
6. Commit and push the new formula to the homebrew-gpush repo

## Team Cheesecake (Caroline and Mike) Next Steps:

- [ ] Finish gpush changes (Nitid)
- [ ] Look into bottles (cheesecake)
- [ ] Update dependency list in forked version --> https://github.com/nitidbit/homebrew-core/Formula/g/gpush.rb
- [ ] Update archive with readme steps [here](https://github.com/nitidbit/gpush/tree/release/v2-hackathon?tab=readme-ov-file#how-to-create-a-new-release-version)
- [ ] Push changes from our forked version then submit PR to homebrew-core
