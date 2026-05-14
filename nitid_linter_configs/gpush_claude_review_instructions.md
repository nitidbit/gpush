# gPush Claude review

Run `gpush diff-branch` first. It should return exactly one git branch name (the base branch).

## Scope

Then review changes from that base to HEAD using:

- `git diff <base>...HEAD`
- `git log <base>..HEAD`
- `git show <sha>` when needed for context

Use the git commit messages to inform your review.

## Review for

- Bugs and regressions
- Typos
- Security vulnerabilities
- Violations of repo conventions
- Anything that should block commit

Do not report low-value style nits or syntax issues that can be handled with tools like Prettier.

## Output format

Format your output for a terminal — plain text, no markdown. Use blank lines for separation and dashes for bullet points. Do not wrap sections in backticks (```).

For each finding include:

- Severity: HIGH | MEDIUM | LOW
- Location: `path/to/file:line` (or range)
- Issue: what is wrong
- Fix: exact recommended change

If no blocking issues, print a brief summary of changes.

## Exit line

The final line must be the word EXIT followed by a number; exactly one of:

- `EXIT 0` (no changes needed)
- `EXIT 1` (issues found)
- `EXIT 2` (could not complete due to tooling/access)
