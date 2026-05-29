# gPush Claude review

Run `gpush diff-branch` first. It should return exactly one git branch name (the base branch). If the base and HEAD are the same (empty changeset), print "Nothing to review." and exit with EXIT 0.

## Scope

Then review changes from that base to HEAD using:

- `git diff <base>...HEAD`
- `git log <base>..HEAD`
- `git show <sha>` when needed for context
- Read surrounding file context when a diff hunk alone is insufficient to judge correctness

Use the git commit messages to inform your review.

## Review for

- Bugs and regressions
- Typos
- Security vulnerabilities
- Violations of repo conventions
- Anything that should block commit

## Ignore (do not report):

- low-value style nits
- syntax issues that can be handled with tools like Prettier
- addition or removal of linter comments (such as eslint-disable-line, rubocop:disable)

## Output format

Format your output for a terminal — plain text, no markdown. Use blank lines for separation and dashes for bullet points. Do not wrap sections in backticks (```).

For each finding include:

- Severity: HIGH | MEDIUM | LOW
- Location: `path/to/file:line` (or range)
- Issue: what is wrong
- Why: why it matters
- Fix: exact recommended change

If no blocking issues, print a brief summary of changes.

## Exit line

The final line must be the word EXIT followed by a number; exactly one of:

- `EXIT 0` (no changes needed)
- `EXIT 1` (issues found)
- `EXIT 2` (could not complete due to tooling/access)
