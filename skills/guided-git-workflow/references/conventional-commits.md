# Conventional Commits 1.0.0 (summary)

Source: https://www.conventionalcommits.org/en/v1.0.0/ (summarized, not copied).

## Format

```
<type>[optional scope][!]: <description>

[optional body]

[optional footer(s)]
```

## Types

| Type | Use for |
|------|---------|
| `feat` | A new feature for users |
| `fix` | A bug fix |
| `docs` | Documentation only |
| `style` | Formatting, whitespace; no code behavior change |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `perf` | Performance improvement |
| `test` | Adding or fixing tests |
| `build` | Build system or dependencies (pyproject, package.json) |
| `ci` | CI configuration (GitHub Actions, pipelines) |
| `chore` | Other maintenance that does not touch src or tests |
| `revert` | Reverts an earlier commit |

## Choosing the type from the staged diff

| What the diff shows | Type |
|---------------------|------|
| Only `*.md`, `docs/` | `docs` |
| Only `tests/`, `test_*.py`, `*.spec.ts` | `test` |
| Only `.github/workflows/`, CI files | `ci` |
| Only `pyproject.toml`, `requirements*.txt`, `package.json`, lock files | `build` |
| New module, new endpoint, new data the app uses | `feat` |
| Change that corrects wrong behavior the user described | `fix` |
| Code moved or renamed with no behavior change | `refactor` |
| `.gitignore`, editor config, scaffolding | `chore` |
| Mixed feature + tests + docs for the same change | the main purpose, usually `feat` or `fix` |

## Scope

Optional, in parentheses, a noun naming the area: `feat(parser):`, `fix(api):`, `docs(readme):`.

- Prefer scopes already used in `git log`.
- Otherwise use the top-level package or folder that changed (`data`, `controller`, `hooks`).
- Leave it out if the change spans many areas.

## Description (header line)

- Imperative mood: "add", "fix", "remove", not "added" / "adds"
- Starts lowercase, no trailing period
- Whole header 72 characters or fewer (50 is ideal)
- Says what changed, not how: `feat(auth): add password reset email`

## Body

- Blank line after the header
- Wrap at 72 characters
- Explain why the change was made and anything a reviewer needs to know
- Skip the body for small, obvious changes

## Footers

- `Refs: PROJ-123` or `Closes #42` for tickets and issues
- `BREAKING CHANGE: <what breaks and how to migrate>` for breaking changes. Also add `!` after the type/scope: `feat(api)!: drop v1 endpoints`
- `Co-authored-by: Name <email>` for pair work

## Examples

```
feat(data): add capability record definitions
```

```
fix(controller): handle empty repository list

The controller crashed with IndexError when no fixture repos were
configured. Return an empty report instead.

Closes #17
```

```
chore: initial project setup

Add pyproject.toml, test layout, and developer tool folders.
```

```
docs(readme): describe fixture repository layout
```

```
feat(api)!: rename capability_id to capability_key

BREAKING CHANGE: clients must send capability_key instead of
capability_id in all requests.
```

## Bad → good

| Bad | Problem | Good |
|-----|---------|------|
| `updated files` | no type, vague | `docs: update setup instructions` |
| `Fix: Login Bug.` | capitalized, period, no detail | `fix(auth): reject expired login tokens` |
| `feat: added new parser and fixed tests and updated readme` | past tense, several changes | split, or `feat(parser): add yaml parser` |
| `WIP` | no meaning | ask the user what the change does |
