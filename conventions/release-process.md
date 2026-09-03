# Release Process

Every `develop → master` merge is a release — no exceptions. Template-only changes go through the same process so all changes are versioned and traceable.

---

## Planning a Release

### Story ticket

Every piece of work needs a Jira story ticket (`NR-XXXXX`) before work begins. The ticket captures:
- What is being changed and why
- Which production surfaces are affected
- Acceptance criteria defining what "production-ready and tested" looks like

### Story lifecycle

```
Story created
  → developed on feature branch
  → tested and production-ready
  → merged to develop
  → linked to release ticket
  → story moved to Done in Jira
```

A story is Done when merged to `develop`, verified, and linked to a release ticket. Stories are not closed on merge to `master`.

### Release ticket

A release ticket is needed before the release PR is raised. It captures:
- All stories included in this release (linked in Jira)
- Which production surfaces are being updated

The release PR cannot be merged without:
- Release ticket linked in the PR description
- Approval on the release ticket from the manager
- Approval on the PR from the tech lead

Non-customer-impacting changes (README updates, CI workflow changes, test additions) do not need a release ticket. If in doubt, create one.

---

## Pre-release Checklist

- [ ] All stories in this release are merged to `develop` and verified
- [ ] All stories are linked to the release ticket in Jira
- [ ] Release ticket is created with the story list and surfaces being updated
- [ ] Every commit on `develop` since the last release is accounted for in the release ticket — run `git log origin/master..origin/develop --oneline` to check
- [ ] All customer-facing commits use `feat:` or `fix:` prefix — if not, push an empty `feat:` commit before merging (see [Known Gaps](./known-gaps.md))
- [ ] CI is passing on `develop`
- [ ] No incomplete changes are on `develop`

---

## What Happens Automatically on Merge to `master`

Semantic-release runs via `release.yml` and:

1. Determines version bump from commits since the last release (`feat:` → minor, `fix:` → patch, `BREAKING CHANGE` → major)
2. Updates `docs/CHANGELOG.md`
3. Bumps version in `package.json` and `package-lock.json`
4. Updates version placeholder in `LogForwarder/index.js`
5. Packages `LogForwarder.zip`
6. Creates a GitHub Release with `LogForwarder/index.js` and `LogForwarder.zip` as assets
7. Uploads `LogForwarder.zip` and SHA256 checksum to Azure Blob Storage (`nrloggingprodreleases`)

ARM and Bicep templates go live on `master` immediately and are versioned by the Git tag created on the same commit.

> The release PR is merged using a **merge commit** — not squash. Squashing collapses all commits into one and causes semantic-release to miss version signals from multiple `feat:` and `fix:` commits.

---

## Post-release Verification

- [ ] GitHub Release created with correct version and assets (`LogForwarder.zip`, `index.js`)
- [ ] `docs/CHANGELOG.md` reflects all changes in this release
- [ ] ARM template deploys end-to-end with the new `releases/latest` artifact
- [ ] Bicep template deploys end-to-end with the new `releases/latest` artifact
- [ ] Logs are flowing to New Relic in the test environment
- [ ] Release ticket updated with the GitHub Release link and closed in Jira
