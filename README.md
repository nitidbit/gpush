gPush
=====

This repo contains files needed for the `gpush` script, which runs tests/linters/etc prior to git push in order to ensure better code


User Setup
----------
If you want to use gPush in your project, here are the ways to run it:

(to be written)


Developer Setup
---------------

[Here are the stories/tickets we are working on:]( https://github.com/orgs/nitidbit/projects/3 )

- **Python**: Python 3 comes by default with MacOS, but you can also get it with Brew: `brew install python`

- **Python packages**:
  ```
  cd gpush
  pip3 install -r requirements.txt
  ```

### Run
To run while developing, execute the gpush module:
    PYTHONPATH=src python3 -m gpush
Notes:
  - "PYTHONPATH=src" — this adds the /src/ folder to be searched for packages
  - "python3 -m gpush" – this says run the __main__.py module inside the gpush package

### Important files

### gpush settings `gpushrc.yml`

| **config key**      | **type**           | **values**                              |
|:--------------------|--------------------|:----------------------------------------|
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
  - *plugin*: `stylelint_plugin_nitid_use_stylekit.js`

### prettier (code formatter) configuration
- *usage*: JavaScript & TypeScript, Ruby, and potentially Scss
- *note*: for convenience, you can use prettier the following ways:
  - set up "format-on-save" in your IDE.  See [here](https://www.educative.io/answers/how-to-set-up-prettier-and-automatic-formatting-on-vs-code)
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

### Step 2: Create the Archive
1. Navigate to Your Repository: Open a terminal and navigate to your local Git repository.
2. Create the Archive: Use the git archive command to create a tarball. For example, if your tag is v1.0.0, run:
```
git archive --format=tar.gz --output=gpush-1.0.0.tar.gz v1.0.0
```
This command creates a tar.gz archive (gpush-1.0.0.tar.gz) of the state of your repository at the tag v1.0.0.

### Step 3: Host the Archive
1. Upload the Archive: You need to upload this .tar.gz file to a publicly accessible place. GitHub Releases is a common choice:
- Go to your GitHub repository page.
- Click on "Releases" or "Tags".
- Find the tag you created (v1.0.0 in this example).
- Click "Edit tag" or "Draft a new release".
- Upload your .tar.gz file in the release assets.
2. Get the Direct Download URL: Once uploaded, get the direct download URL for the .tar.gz file. It will be something like https://github.com/username/reponame/releases/download/v1.0.0/gpush-1.0.0.tar.gz.

### Step 4: Update Your Homebrew Formula
1. Update the url Field: In your Homebrew formula, set the url field to the direct download URL of your tarball.
2. Update the sha256 Field: Calculate the SHA256 checksum of the tarball and update the sha256 field in your formula. Use:
```
shasum -a 256 gpush-1.0.0.tar.gz
```
3. Test the Formula: Finally, test your formula locally to ensure it downloads and installs correctly.

By following these steps, you create a stable, versioned release of your software that can be easily integrated into a Homebrew formula. Remember, the key is to ensure that the url and sha256 in your Homebrew formula match the uploaded tarball.

## Team Cheesecake (Caroline and Mike) Next Steps:
- [ ] Finish gpush changes (Nitid)
- [ ] Look into bottles (cheesecake)
- [ ] Update dependency list in forked version --> https://github.com/nitidbit/homebrew-core/Formula/g/gpush.rb 
- [ ] Update archive with readme steps [here](https://github.com/nitidbit/gpush/tree/release/v2-hackathon?tab=readme-ov-file#how-to-create-a-new-release-version)
- [ ] Push changes from our forked version then submit PR to homebrew-core
