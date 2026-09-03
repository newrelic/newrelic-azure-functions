# Branching & Commit Standards

## Branches

### Long-lived branches

- `develop` — integration branch. All work lands here first. Always kept production-ready.
- `master` — release branch. Every merge here is a release. Only the release PR from `develop` merges here.

### Branch naming

| Type | Convention | Base |
|---|---|---|
| New feature or enhancement | `feature/NR-XXXXX-short-description` | `develop` |
| Bug fix | `fix/NR-XXXXX-short-description` | `develop` |
| Internal change, no customer impact | `chore/short-description` | `develop` |

Branch names are lowercase and hyphen-separated. All branches include the Jira ticket number except `chore/` branches. Feature branches are deleted after merging.

### Flow

```
master
  └── develop
        ├── feature/NR-XXXXX-...   → PR → develop
        ├── fix/NR-XXXXX-...       → PR → develop
        └── chore/...              → PR → develop

develop → release PR → master (every release)
```

No direct commits to `develop` or `master` — all changes go through a PR.

---

## Commit Messages

This repo uses [Conventional Commits](https://www.conventionalcommits.org/). Semantic-release reads commit messages to determine the version bump and whether a GitHub Release is created.

### Format

```
<type>(optional scope): <short description>

[optional body — explains the why, not the what]

[optional footer: NR-XXXXX]
```

Short description is lowercase, present tense, no period at the end.

### Types

| Type | When to use | Version bump |
|---|---|---|
| `feat` | New feature, new template parameter, new forwarder capability | Minor (3.3.1 → 3.4.0) |
| `fix` | Bug fix, template correction, CVE fix | Patch (3.3.1 → 3.3.2) |
| `chore` | CI changes, non-security dependency bumps — zero customer impact | No release |
| `docs` | README, migration guides | No release |
| `test` | Test changes only | No release |

Any change to `armTemplates/`, `bicep/`, or `LogForwarder/` uses `feat:` or `fix:`. Using `chore:` on customer-facing files skips the release and leaves templates unversioned.

### Examples

- `feat(event-hub): add Flex Consumption plan support`
- `fix(blob-forwarder): handle empty container name gracefully`
- `chore(deps): bump @azure/functions to 4.11.2`
- `fix(deps): upgrade axios to patch CVE-2024-XXXXX`
- `docs: add migration guide for Flex Consumption`
- Breaking change — `BREAKING CHANGE:` in the footer triggers a major version bump:
  ```
  feat(arm-template): drop support for legacy consumption plan

  BREAKING CHANGE: scalingMode=Basic is no longer supported
  ```

### PR title

For `feature/fix/chore → develop` PRs, the PR title becomes the commit message after squash merge — it should follow the same conventional commit format.
