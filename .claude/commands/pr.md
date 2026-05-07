---
description: Open a pull request for the current branch using .github/PULL_REQUEST_TEMPLATE.md
argument-hint: "[optional extra context for the PR description]"
---

Open a pull request for the current branch, filling in `.github/PULL_REQUEST_TEMPLATE.md` based on what actually changed.

Extra context from the user (may be empty): $ARGUMENTS

## Step 1 — Survey the branch

Run these in parallel:

- `git status` (no `-uall`)
- `git rev-parse --abbrev-ref HEAD` to confirm the current branch
- `git rev-parse --abbrev-ref --symbolic-full-name @{u}` to see if it tracks a remote (may fail — that's fine, means the branch isn't pushed yet)
- `git log main..HEAD --oneline` for the commit list
- `git diff main...HEAD --stat` for a file-level summary
- `git diff main...HEAD` for the full diff
- Read `/Users/jcarter/src/writing-buddy/.github/PULL_REQUEST_TEMPLATE.md`

If the current branch is `main`, stop and tell the user — no PR to open.

## Step 2 — Bump the version

The Xcode project tracks two values in `WritingBuddy.xcodeproj/project.pbxproj`, each present in **4 configurations** (app Debug/Release, tests Debug/Release):

- `MARKETING_VERSION` — semver `MAJOR.MINOR.PATCH` (e.g. `1.0.1`)
- `CURRENT_PROJECT_VERSION` — monotonic build number

Read the current values (`grep -nE '(MARKETING_VERSION|CURRENT_PROJECT_VERSION)' WritingBuddy.xcodeproj/project.pbxproj`), then decide the bump from the diff:

- **Patch** (default): bug fixes, refactors, internal-only work, tests, docs, build/tooling tweaks, dependency bumps without behavior change.
- **Minor**: a new user-visible feature, a new screen/module, a new provider integration, or any meaningful capability addition.
- **Major**: a breaking change, removal of a major feature, fundamental UX overhaul, or anything the user should explicitly opt into. **Always pause and confirm with the user before bumping major.** Show your reasoning and the proposed new version.

Always increment `CURRENT_PROJECT_VERSION` by 1, regardless of which semver part bumps.

Apply the changes with `Edit` using `replace_all: true` so all 4 configurations stay in sync. Then commit just the pbxproj change with a message like:

```
Bump version to <new version> (build <new build>)
```

Do not bundle other unrelated changes into this commit.

## Step 3 — Draft the PR

Read every commit in the range, not just the latest. Synthesize a PR body that follows the template *exactly* (section order, headings, checkboxes), filling in real content drawn from the diff and commit history:

- **Title**: short (under 70 chars), imperative mood, no trailing period. Don't restate the branch name.
- **Summary**: 1–3 bullets covering what changed and why. Lead with the user-visible change when there is one.
- **Type of Change**: tick the boxes that apply based on the diff (e.g. UI files changed → UI/UX update, new `*.swift` file with a new feature → New feature, etc.). Leave others unchecked.
- **Related Issues**: leave the placeholders unless the user's `$ARGUMENTS` mention an issue number.
- **User Impact**: what someone using the app will notice. If purely internal, say so.
- **Implementation Notes**: call out non-obvious decisions you can see from the diff (new abstractions, AppKit interop, schema changes, etc.). Skip if the change is trivial.
- **Screenshots or Recordings**: leave the table empty but keep the header — the user will paste in screenshots themselves.
- **Test Plan**: tick `Built successfully with xcodebuild` only if you can confirm a successful build occurred on this branch (e.g., from session context). Otherwise leave unchecked. Tick others only when you have direct evidence. Fill in the Commands run code block with any `xcodebuild` / test commands that were actually run; otherwise leave it empty.
- **Risk and Rollback**: short, specific. "Rollback: revert commit `<sha>`" is fine.
- **Release Notes**: one user-facing line, or `None` for internal-only changes.
- **Reviewer Checklist**: leave all unchecked — the reviewer ticks these.

If `$ARGUMENTS` is non-empty, weave that context into the Summary / Implementation Notes / Risk sections where it fits.

## Step 4 — Confirm before pushing

Show the user the drafted title and body (and a one-line reminder of the version bump applied in Step 2) and ask if they want to proceed. Do NOT push or create the PR until they confirm.

## Step 5 — Push and create

After confirmation, run in parallel where possible:

- If the branch has no upstream (step 1 showed no `@{u}`), `git push -u origin HEAD`. Otherwise `git push` (the version-bump commit from step 2 makes this branch ahead of remote).
- `gh pr create --title "<title>" --body "$(cat <<'EOF'\n<body>\nEOF\n)"` — pass the body via heredoc so markdown formatting is preserved.

Do not append a "Generated with Claude Code" footer — the project template doesn't include one.

Return the PR URL printed by `gh pr create` so the user can open it.

## Guardrails

- Never force-push.
- Never push to `main` directly.
- If `gh` is missing or unauthenticated, stop and tell the user to run `gh auth login` themselves (suggest `! gh auth login` so it runs in their session).
- If there are uncommitted changes, ask the user whether to include them in a new commit before opening the PR, or proceed without them.
