---
name: "guided-git-workflow"
description: "Guide the user step by step through reviewing repo status, creating a Conventional Branch, staging files, writing a Conventional Commit message, adding the GitHub remote, and pushing, asking for confirmation before every action. Use when the user wants to commit, create a branch, add a remote, or push their work to GitHub interactively."
license: "MIT"
compatibility: "Requires git 2.23+ on PATH. Written for Windows PowerShell 5.1+ and PowerShell 7; the git commands also work in bash."
metadata:
  author: "HP"
  version: "1.0.0"
---

# Guided Git Workflow

## Overview

This skill walks the user through a complete "save my work to GitHub" flow, one step at a time:

1. Pre-flight check (git installed, repo exists, identity set)
2. Show current status: branch, tracked files, staged, modified, untracked, remotes, recent commits
3. Suggest a branch name that follows Conventional Branch 1.1.0, then create or switch to it
4. Stage files
5. Write the commit message (the user's own, or one suggested from the conversation and the staged diff), then commit
6. Ask for the GitHub remote URL and add it
7. Push to the branch (pushing to `main`/`master`/`develop` needs its own explicit confirmation)

The agent never runs a command that changes the repository without the user's explicit "yes" for that specific step.

## The Confirmation Contract (read first, always applies)

These rules override everything else in this skill.

1. **One step per turn.** Do the read-only checks for the current step, present the proposal, then end the turn with a question. Do not chain mutating steps together.
2. **Mutating commands need an explicit yes for that step.** Mutating commands are: `git init`, `git switch`/`git checkout`, `git add`, `git restore --staged`, `git commit`, `git remote add`/`set-url`/`remove`, `git push`, `git pull`, `git config`, and edits to `.gitignore`.
3. **Read-only commands can run without asking.** These are: `git status`, `git log`, `git diff`, `git branch`, `git remote -v`, `git ls-files`, `git rev-parse`, `git config --get`, `git check-ref-format`, and the scripts in `scripts/`.
4. **Show the exact command before running it.** The user approves the command, not a description of it.
5. **Accept these replies at every step:**
   - `yes` / `ok` / `proceed`: run the proposed command
   - `edit ...`: change the proposal (new branch name, different files, different message), then show it again and ask again
   - `skip`: skip this step and move to the next one
   - `stop`: end the workflow and summarize what was done so far
6. **Silence or ambiguity is not consent.** If the reply is unclear ("hmm", "maybe", a question), answer it and ask again.
7. **Never use** `--force`, `--force-with-lease`, `git reset --hard`, `git clean`, `git push --delete`, `git branch -D`, or `--no-verify`, unless the user asks for that exact command by name. Even then, explain what it destroys and ask a second time.
8. **Never put credentials in commands or URLs.** If the user pastes a URL with a token in it (`https://user:token@github.com/...`), refuse to use it, tell them it exposes the token, and ask for the plain URL.
9. **If a confirm-gate hook prompts in the IDE** (see "Optional: hard confirmation gate"), that prompt is in addition to the chat confirmation, not a replacement for it.

### Message format for every step

Use this layout so each step looks the same:

```
### Step N of 6: <title>

<What I found: short table or list>

**Proposal:** <one sentence>

    <exact command(s)>

Reply **yes** to run it, **edit** to change it, **skip**, or **stop**.
```

## Prerequisites Checklist

- [ ] `git` 2.23 or newer is on PATH (`git switch` needs 2.23)
- [ ] The workspace folder is the project the user wants to push
- [ ] The GitHub repository already exists (this skill does not create GitHub repos or pull requests)
- [ ] The user can sign in to GitHub. On Windows, Git Credential Manager (bundled with Git for Windows) opens a browser sign-in on the first push.

## Helper Scripts

All scripts are in `scripts/` next to this file, are read-only, and print JSON.

| Script | Purpose |
|--------|---------|
| `scripts/Test-BranchName.ps1` | Validate a branch name against Conventional Branch 1.1.0, or build one from a type and free text |
| `scripts/Test-RemoteUrl.ps1` | Validate a GitHub remote URL and reject URLs with embedded credentials |
| `scripts/Find-RiskyFiles.ps1` | Flag likely secrets and large files among changed and untracked files |
| `scripts/git-confirm-gate.ps1` | Optional PreToolUse hook that makes the IDE ask before `git commit` / `git push` |

Run them with an absolute path to the script and the repo as the working directory:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\Test-BranchName.ps1" -Name "feature/add-login-page"
```

Replace `<skill-dir>` with the folder that contains this SKILL.md.

## Step-by-Step Guide

### Step 0: Pre-flight (read-only, no confirmation needed unless something must change)

Run:

```powershell
git --version
git rev-parse --is-inside-work-tree
git rev-parse --show-toplevel
git config --get user.name
git config --get user.email
```

Handle these cases:

- **git not found:** stop. Tell the user to install Git for Windows from https://git-scm.com/download/win and reopen the IDE.
- **Not a git repository:** propose initializing one. Ask which initial branch name they want (default `main`):

  ```powershell
  git init -b main
  ```

  Wait for yes.
- **Repo root is not the workspace folder:** tell the user which folder is the repo root and ask if that is the repo they meant.
- **`user.name` or `user.email` empty:** ask the user for both values. Propose setting them for this repository only (not `--global`):

  ```powershell
  git config user.name "Their Name"
  git config user.email "they@example.com"
  ```

  Wait for yes.

If nothing needs to change, say so in one line and go straight to Step 1 in the same turn.

### Step 1 of 6: Show current status (read-only)

Collect:

```powershell
git status --short --branch --untracked-files=all
git branch --show-current
git rev-parse --verify -q HEAD          # fails on a repo with no commits yet
git ls-files | Measure-Object -Line     # count of tracked files
git diff --stat
git diff --staged --stat
git log --oneline -n 5                  # skip if there are no commits
git branch --list
git remote -v
git rev-parse --abbrev-ref --symbolic-full-name "@{u}"   # upstream; fails if none
```

Also run the risky-file scan:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\Find-RiskyFiles.ps1"
```

Present a summary:

| Item | Value |
|------|-------|
| Current branch | `main` (no commits yet) |
| Upstream | none |
| Tracked files | 42 |
| Staged | 0 files |
| Modified (unstaged) | 3 files |
| Untracked | 5 files |
| Remotes | none |
| Last commits | ... |

Then list the files by group (staged, modified, deleted, untracked). If there are more than 30 files in a group, show the first 30 and the count of the rest, grouped by folder.

If the risky-file scan found anything, show a warning block with the file and the reason (never the matched secret value) and suggest adding those paths to `.gitignore` in Step 3.

If there is nothing to commit and the branch has no unpushed commits, say so and ask whether the user still wants to add a remote or push.

End with: "Shall I suggest a branch name next?" and wait.

### Step 2 of 6: Suggest and create the branch

#### 2.1 Choose the type

Use the Conventional Branch types in [references/conventional-branch.md](references/conventional-branch.md). Default to the full purpose prefixes:

| Work described in the conversation / diff | Branch type |
|------------------------------------------|-------------|
| New capability, new feature | `feature/` |
| Non-urgent bug fix | `bugfix/` |
| Urgent production fix | `hotfix/` |
| Preparing a release | `release/` |
| Docs, dependencies, config, tooling, refactors, tests, CI | `chore/` |

If existing branches (`git branch --list` and `git branch -r`) already use the short aliases `feat/` or `fix/`, follow the repository's habit and mention it.

Do not use AI-agent prefixes (`ai/`, `claude/`, ...) unless the user asks for them.

#### 2.2 Write the description

Base it on what the user said they were working on in this conversation, checked against the actual changed files. Rules:

- lowercase `a-z`, digits, hyphens, and dots only
- 2 to 5 words, about 40 characters or fewer
- include a ticket number if the user mentioned one (`PROJ-123` becomes `proj-123`)
- no leading, trailing, or repeated hyphens or dots

Validate the proposal and one or two alternatives:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\Test-BranchName.ps1" -Name "feature/add-capability-record"
```

or build one from free text:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\Test-BranchName.ps1" -Type feature -Description "Add capability record JSON"
```

Only propose names where `"valid": true`.

#### 2.3 Present the choice

```
### Step 2 of 6: Branch

You are on `main`. Based on our conversation (adding the capability record data file),
I suggest:

1. `feature/add-capability-record`  (recommended)
2. `chore/add-capability-data`
3. Stay on `main` (not recommended: commits go straight to the trunk)

    git switch -c feature/add-capability-record

Reply **yes**, **1/2/3**, **edit <name>**, **skip**, or **stop**.
```

Cases:

- **User types their own name:** validate it. If invalid, show the errors from the script and a corrected version, and ask again.
- **Branch already exists locally:** offer `git switch <name>` instead of `-c`, or a different name.
- **Branch exists only on the remote** (`origin/<name>`): offer `git switch <name>` (git creates a tracking branch).
- **Uncommitted changes and switching to an existing branch:** warn that git may refuse if the changes conflict. Never stash or discard without asking.
- **No commits yet:** `git switch -c <name>` renames the unborn branch. That is fine and nothing is lost. Mention that `main` will not exist until something is pushed to it.
- **User chooses to stay on a trunk branch:** record that choice; Step 6 will still ask the separate trunk-push confirmation.

After running the command, confirm with `git branch --show-current` and move to Step 3 in the next turn.

### Step 3 of 6: Stage files

Show what would be staged:

```powershell
git status --short --untracked-files=all
```

Propose one of these, based on the conversation:

- **Everything:** `git add -A`
- **Selected files** (when the conversation was about specific files, or other changes look unrelated):

  ```powershell
  git add -- "src/reverse_engineer/data/capability_record.json" "docs/kiro-verification.md"
  ```

- **Everything except risky files:** propose adding those paths to `.gitignore` first (show the exact lines to append), then `git add -A`.

Present the file list with a marker per file (`+` will be staged, `-` will be left out, `!` flagged by the risky-file scan). Ask yes / edit / skip / stop.

Rules:

- Always quote paths and put `--` before them, so file names starting with `-` or containing spaces work.
- Never stage files flagged by `Find-RiskyFiles.ps1` unless the user names them and confirms after seeing the warning.
- If the user says "unstage X", propose `git restore --staged -- "X"` and ask.

After staging, show the result and keep it for Step 4:

```powershell
git diff --staged --stat
```

### Step 4 of 6: Commit message and commit

#### 4.1 Ask how the user wants the message

Ask both at once, so the user can pick without an extra round trip:

```
### Step 4 of 6: Commit message

Do you want to write your own message, or use my suggestion?

Suggested (from our conversation and the staged diff):

    feat(data): add capability record definitions

    Add capability_record.json with the initial capability entries used
    by the reverse-engineer engine.

Reply **yes** to use it, **edit** to change it, or type your own message.
```

#### 4.2 Build the suggestion

Use [references/conventional-commits.md](references/conventional-commits.md). Sources, in priority order:

1. `git diff --staged` (what actually changed; the source of truth)
2. This conversation (why it changed, ticket numbers, the user's own wording)
3. `git log --oneline -n 10` (scope names and style the repo already uses)

Header rules: `<type>(<optional scope>): <description>`, imperative mood ("add", not "added"), lowercase start, no trailing period, 72 characters or fewer. Add a body (wrapped at 72) when the "why" is not obvious from the header. Add `Refs: <ticket>` if the user mentioned one. Use `!` and a `BREAKING CHANGE:` footer only if the change breaks existing users.

Do not claim things the diff does not show. If the conversation mentions work that is not staged, leave it out of the message and tell the user it is not staged.

If the staged diff mixes unrelated changes, say so and offer to split into separate commits (go back to Step 3 with a narrower selection).

#### 4.3 If the user writes their own message

- Use their text. Fix nothing silently.
- If it does not follow Conventional Commits, show a reformatted version next to theirs and ask which to use. If they keep theirs, use theirs.

#### 4.4 Commit

Write the approved message to a temporary file and commit with `-F`. This avoids PowerShell quoting problems with quotes, backticks, `$`, and multi-line text:

```powershell
$msgFile = Join-Path $env:TEMP "git-guided-flow-commit-msg.txt"
[System.IO.File]::WriteAllText($msgFile, "feat(data): add capability record definitions`n`nAdd capability_record.json with the initial capability entries used`nby the reverse-engineer engine.`n", (New-Object System.Text.UTF8Encoding($false)))
git commit -F $msgFile
Remove-Item $msgFile
```

Show the exact message in the proposal before running. After the commit, show:

```powershell
git log --oneline -n 1
git show --stat --oneline HEAD
```

If a pre-commit hook fails: show its output, help fix the problem, re-stage, and propose the commit again. Never use `--no-verify` or `--amend` to get around it.

### Step 5 of 6: Remote repository

Check what exists:

```powershell
git remote -v
```

**No remote yet.** Ask the user for the GitHub repository link:

```
### Step 5 of 6: Remote

This repository has no remote. Please paste the GitHub repository URL, for example:

- https://github.com/<owner>/<repo>.git
- git@github.com:<owner>/<repo>.git
```

Validate what they paste:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\Test-RemoteUrl.ps1" -Url "https://github.com/owner/repo.git"
```

If valid, propose:

```powershell
git remote add origin "https://github.com/owner/repo.git"
```

**`origin` already exists.** Show its URL and ask:

1. Keep it (recommended if it is the right repo)
2. Replace it: `git remote set-url origin "<new-url>"`
3. Add the new URL under another name: `git remote add <name> "<new-url>"`

After changing remotes, run `git remote -v` and show the result.

Optional reachability check: offer to run `git ls-remote --heads origin`. Ask first, because it may open a GitHub sign-in window. Its output also tells you whether the remote is empty and which branches exist there, which matters for Step 6.

### Step 6 of 6: Push

#### 6.1 Work out the push target

```powershell
git branch --show-current
git rev-parse --abbrev-ref --symbolic-full-name "@{u}"   # upstream, if any
git status -sb                                           # ahead/behind
```

Default proposal: push the current branch to a branch of the same name on the remote and set upstream:

```powershell
git push -u origin feature/add-capability-record
```

#### 6.2 Trunk branches need a separate confirmation

If the push target is `main`, `master`, or `develop` (either the current branch is a trunk branch, or the user asks to push to one), ask a dedicated question before anything else:

```
You are about to push directly to `main` on origin. This skips review.
Do you want to push to `main`? Reply **yes, push to main** to confirm,
or **no** to push `feature/add-capability-record` instead.
```

Require a reply that clearly names the trunk branch (for example "yes, push to main"). A plain "yes" to an earlier step does not count.

If the user is on a feature branch and wants the work on `main`, offer these options and let them choose:

1. Push the feature branch and open a pull request on GitHub (recommended)
2. Push the feature branch's commits to remote `main`: `git push origin feature/add-capability-record:main`
3. Switch to `main`, merge the feature branch, then push `main`:

   ```powershell
   git switch main
   git merge --no-ff feature/add-capability-record
   git push -u origin main
   ```

   Each of these three commands is its own confirmation.

If the remote is empty (no branches), mention that the first branch pushed usually becomes the default branch on GitHub. If they push a feature branch first, they may want to push `main` too, or change the default branch in GitHub settings.

#### 6.3 Run the push

Ask yes / edit / skip / stop, then run the command. Git Credential Manager may open a browser sign-in on the first push; tell the user to complete it.

On success, show:

```powershell
git status -sb
git log --oneline -n 3
```

and the pull request link for non-trunk branches:

```
https://github.com/<owner>/<repo>/pull/new/<branch>
```

(`Test-RemoteUrl.ps1` returns `webUrl`, which is the base for this link.)

#### 6.4 If the push is rejected

- **`rejected ... (fetch first)` or `non-fast-forward`:** the remote has commits you do not have. Explain this, and offer `git pull --rebase origin <branch>` (ask first). Never offer `--force` as the fix.
- **Remote has an initial commit (README/license) and local history is unrelated:** explain the two histories, and offer `git pull --rebase origin main` or, with a clear explanation, `git pull origin main --allow-unrelated-histories`. Ask before either.
- **`Permission denied` / `403`:** the signed-in account cannot write to this repo. Ask the user to check the account and repo permissions.
- **`Repository not found`:** wrong URL, a private repo the account cannot see, or a typo. Go back to Step 5.

### Final summary

When the workflow ends (completed or stopped), give a short summary:

| Item | Result |
|------|--------|
| Branch | `feature/add-capability-record` (created) |
| Files committed | 3 |
| Commit | `a1b2c3d feat(data): add capability record definitions` |
| Remote | `origin` → https://github.com/owner/repo.git (added) |
| Push | pushed, upstream set |
| Next step | open PR: https://github.com/owner/repo/pull/new/feature/add-capability-record |

List any step the user skipped.

## Common Workflows

### Workflow: First push of a brand-new project
**Goal:** a local folder with no git history ends up on GitHub.

Step 0 runs `git init -b main` (confirmed), Step 1 shows everything as untracked, Step 2 suggests `chore/initial-project-setup` or staying on `main`, Step 3 usually needs `.gitignore` lines for `.venv/`, `__pycache__/`, `.env`, `node_modules/`, Step 5 asks for the URL, Step 6 pushes. For a first commit, many users prefer `main`; if they stay on `main`, Step 6 still asks the trunk question.

### Workflow: Commit only, no push
The user replies `skip` at Steps 5 and 6. Summarize and remind them nothing was pushed.

### Workflow: Push existing commits
If Step 1 shows nothing to commit but the branch is ahead of its upstream, offer to skip Steps 3 and 4 and go to Step 6.

### Workflow: Several commits in one session
After Step 4, ask whether there is more to commit. If yes, loop back to Step 3 with the remaining files before going to Step 5.

## Optional: hard confirmation gate

Chat confirmations depend on the agent following this skill. For an extra IDE-level prompt before every `git commit` and `git push`, add a PreToolUse hook in the workspace (`.kiro/hooks/`) that runs `scripts/git-confirm-gate.ps1`. The hook matches the shell tools and prints a `permissionDecision: "ask"` decision when the command contains `git commit` or `git push`. Ask Kiro to create it with the `createHook` tool:

- trigger: `PreToolUse`
- matcher: `execute_pwsh|control_pwsh_process`
- action: command `powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\git-confirm-gate.ps1"`

## Troubleshooting

### PowerShell shows git output in red as `NativeCommandError`
**Cause:** git writes progress and informational messages (such as "Switched to a new branch") to stderr. Windows PowerShell 5.1 wraps stderr lines from native commands as errors when they are redirected.
**Solution:** check `$LASTEXITCODE`. If it is `0`, the command succeeded; ignore the red text.

### Error: "fatal: not a git repository"
**Cause:** the workspace has no `.git` folder.
**Solution:** go back to Step 0 and offer `git init -b main`.

### Error: "Author identity unknown"
**Cause:** `user.name` / `user.email` are not set.
**Solution:** Step 0 asks for them and sets them for this repo only, after confirmation.

### Error: "src refspec <branch> does not match any"
**Cause:** pushing a branch that has no commits.
**Solution:** go back to Step 4 and commit first.

### Error: "fatal: remote origin already exists"
**Cause:** `git remote add origin` when `origin` is already set.
**Solution:** Step 5 offers keep / `set-url` / add under another name.

### Push hangs with no output
**Cause:** Git Credential Manager is waiting for a sign-in window that may be behind the IDE.
**Solution:** ask the user to look for the GitHub sign-in window. If it never appears, ask them to run the same `git push` command in their own terminal.

### Error: "File ... exceeds GitHub's file size limit of 100.00 MB"
**Cause:** a file over 100 MB was committed.
**Solution:** explain that the commit must be changed before pushing. Offer to remove the file from the last commit with `git rm --cached -- "<file>"`, add it to `.gitignore`, and create a new commit, asking before each command. Suggest Git LFS for files that must be versioned.

## Best Practices

- Ask before every change; run read-only checks freely.
- Treat the staged diff as the truth for the commit message; use the conversation for intent and wording.
- Keep branch descriptions short and specific; reuse ticket numbers the user mentions.
- Prefer feature branches plus pull requests over pushing to `main`.
- Never print secret values; refer to flagged files by path and reason only.
