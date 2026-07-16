# gPush Claude review

The base ref for this review is stated at the top of this prompt. Review the changes from that base ref to HEAD.

## Scope

Review the changes using:

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

Format your output for a terminal — plain text, no markdown. Use blank lines for separation and dashes for bullet points.

Do NOT use triple backticks (```) anywhere in your response. Do not wrap the whole review, any section, any code snippet, or any file path in a code fence. Output the review text directly.

For each finding include:

- Severity: HIGH | MEDIUM | LOW
- Location: `path/to/file:line` (or range)
- Issue: what is wrong
- Why: why it matters
- Fix: exact recommended change (including code if appropriate)

If no blocking issues, print a brief summary of changes.

## Exit line

End with an exit line: the word EXIT, a single space, then a single digit — and nothing else on that line. The line must be exactly `EXIT 0`, `EXIT 1`, or `EXIT 2`.

This must be the very last line of your entire response. Output absolutely nothing after it — no closing remarks, no summary sentence, no punctuation, no blank line followed by text, and no code fence. The EXIT line is the final thing you write.

Choose the digit by this meaning:

- 0 — No changes needed - code is OK to push
- 1 — Blocking issues found - should be fixed before push
- 2 — could not complete due to tooling/access
