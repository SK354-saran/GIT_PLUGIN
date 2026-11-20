# Conventional Branch 1.1.0 (summary)

Source: https://conventionalbranch.org/ (summarized, not copied).

## Format

```
<type>/<description>
```

Trunk branches `main`, `master`, and `develop` have no prefix.

## Types

| Type | Use for | Example |
|------|---------|---------|
| `feature/` (alias `feat/`) | New features | `feature/add-login-page` |
| `bugfix/` (alias `fix/`) | Bug fixes | `bugfix/fix-header-bug` |
| `hotfix/` | Urgent fixes | `hotfix/security-patch` |
| `release/` | Release preparation | `release/v1.2.0` |
| `chore/` | Non-code work: dependencies, docs, config | `chore/update-dependencies` |
| `ai/` | Any AI agent (vendor-neutral) | `ai/refactor-auth-flow` |
| `claude/`, `codex/`, `copilot/`, `cursor/` | Branches created by those AI agents | `claude/security-patch` |

Any other type (for example `docs/`, `test/`, `experiment/`) is not valid under the spec. Teams can add their own as a documented extension; this skill does not.

Conventional Commits has more types (`docs`, `ci`, `refactor`, `test`, ...) than Conventional Branch. Map them like this:

| Commit type | Branch type |
|-------------|-------------|
| `feat` | `feature/` |
| `fix` | `bugfix/` (or `hotfix/` if urgent) |
| `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore` | `chore/` |
| release commit | `release/` |

## Description rules

- Only lowercase `a-z`, digits `0-9`, hyphens `-`, and dots `.`
- No uppercase, spaces, underscores, slashes, or other symbols
- No consecutive hyphens or dots (`new--login`, `v1..2`)
- No hyphen next to a dot (`v1.-2.0`)
- No leading or trailing hyphen or dot
- Dots are usually for versions (`release/v1.2.0`, `chore/upgrade-node-v20.11`)
- Include the ticket number if there is one, lowercased: `feature/proj-123-new-login`
- Keep it short and specific

## Grammar (ABNF)

```
branch-name     = trunk-branch / prefixed-branch
trunk-branch    = "main" / "master" / "develop"
prefixed-branch = type "/" description
type            = "feature" / "feat" / "bugfix" / "fix"
                / "hotfix" / "release" / "chore"
                / "ai" / "copilot" / "cursor"
                / "claude" / "codex"
description     = desc-segment *("-" desc-segment)
desc-segment    = 1*(ALPHA / DIGIT) *("." 1*(ALPHA / DIGIT))
ALPHA           = %x61-7A   ; lowercase a-z
DIGIT           = %x30-39   ; 0-9
```

Equivalent regex used by `scripts/Test-BranchName.ps1`:

```
^(main|master|develop)$|^(feature|feat|bugfix|fix|hotfix|release|chore|ai|copilot|cursor|claude|codex)/[a-z0-9]+(\.[a-z0-9]+)*(-[a-z0-9]+(\.[a-z0-9]+)*)*$
```

## Quick check table

| Name | Valid | Why |
|------|-------|-----|
| `feature/add-login-page` | yes | |
| `feat/add-login-page` | yes | alias |
| `release/v1.2.0` | yes | dots in version |
| `feature/proj-123-new-login` | yes | ticket number |
| `Feature/Add-Login` | no | uppercase |
| `feature/new--login` | no | consecutive hyphens |
| `feature/-new-login` | no | leading hyphen |
| `feature/new-login-` | no | trailing hyphen |
| `release/v1.-2.0` | no | hyphen next to dot |
| `fix/header bug` | no | space |
| `fix/header_bug` | no | underscore |
| `docs/update-readme` | no | `docs` is not a branch type; use `chore/update-readme` |
