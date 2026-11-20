---
description: Create a pull request for the current branch. Shows a summary for review before opening the PR.
argument-hint: [optional PR title or description]
---

Create a GitHub pull request for the current branch.

## Step 1 — Understand the changes

The base branch for all PRs is `main`.

Run the following to understand what this PR contains:
- `git status` — check for any uncommitted changes (warn the user if there are any)
- `git log main..HEAD --oneline` — list all commits in this branch
- `git diff main...HEAD` — review the full diff against the base branch

## Step 2 — Draft the PR

Write a pull request with:

**Title** — short, under 70 characters, describing what this PR does

**Body** with these sections:
- `## Summary` — 2–4 bullet points describing what changed and why
- `## How to test` — clear steps to verify the changes work
- `## Notes` — any context, caveats, or follow-up work (omit if not needed)

If $ARGUMENTS is provided, use it as the starting point for the title and summary.

Show the full draft to the user and ask: "Does this look right for the PR? Reply yes to create it, or tell me what to change."

**Always wait for explicit approval before creating the PR.**

## Step 3 — Create the PR

Only after the user approves:

```bash
gh pr create --base main --title "<title>" --body "$(cat <<'EOF'
<body>

🤖 Created with [Claude Code](https://claude.ai/claude-code)
EOF
)"
```

## Step 4 — Return the PR URL and remind the user to review

After the PR is created, print the PR URL clearly so the user can open it immediately.

Then show this message:

> "PR is open and ready. Please review the code before merging into main — check for anything that looks unintended, and make sure the diff matches what you expected."
