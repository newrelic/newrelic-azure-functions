# Engineering Standards — newrelic-azure-functions

---

## Project Overview

This repo contains Azure Functions that collect and forward logs from Microsoft Azure to the New Relic Logs API:

- **Blob Forwarder** — triggered by new blobs in Azure Blob Storage
- **Event Hub Forwarder** — triggered by messages on an Azure Event Hub

### Production Surfaces

| Surface | Files | Goes live | Who is affected |
|---|---|---|---|
| ARM templates | `armTemplates/azuredeploy-*.json` | Merge to `master` | NR integration page ("Deploy to Azure" button) and direct ARM deployments |
| Bicep templates | `bicep/azuredeploy-*.bicep` | Merge to `master` | Customers deploying directly via Bicep CLI |
| Function code | `LogForwarder/` | GitHub Release created | All customers — ARM and Bicep templates both pull from `releases/latest/download/LogForwarder.zip` |

There is no staging buffer — template changes are live on master merge, and a GitHub Release is created automatically by semantic-release when `feat:` or `fix:` commits land on `master`.

---

## Implementation

### Branching strategy

`master` is production — only tested, reviewed, and release-ready changes land here. `develop` is the active development branch and only contains complete work that is ready to ship at any point.

**Single-story work** — branch directly off `develop`, raise a PR back to `develop`:

```
develop
  └── feature/NR-XXXXX-description  →  develop  (squash merge)
```

**Multi-story feature** — create a parent feature branch off `develop`. Each story branches off the parent and merges back into it. The parent merges to `develop` only when the entire feature is complete:

```
develop
  └── feature/parent-feature-name
        ├── feature/NR-XXXXX-story-one  →  parent  (squash merge)
        └── feature/NR-YYYYY-story-two  →  parent  (squash merge)
             ↓
           develop  (merge commit — preserves all story commits)
```

This keeps `develop` free of in-progress work from unfinished features.

### Branch naming

| Branch type | Pattern | Example |
|---|---|---|
| Single story / bug fix | `feature/NR-XXXXX-description` or `fix/NR-XXXXX-description` | `feature/NR-12345-add-flex-consumption` |
| Multi-story parent | `feature/short-description` | `feature/flex-consumption` |
| Non-customer work | `chore/short-description` | `chore/update-ci-workflow` |

### Merge methods

| Merge | Method |
|---|---|
| Story → `develop` or parent feature branch | Squash merge |
| Parent feature branch → `develop` | Merge commit |
| `develop` → `master` (release PR) | Merge commit |

Delete feature branches after merging. `develop` and `master` are never deleted.

### PR titles

All merges to `develop` are squash merges — the PR title becomes the commit on `develop`. PR titles must follow conventional commit format:

```
<type>(<scope>): <subject>
```

| Type | Triggers release | Use for |
|---|---|---|
| `feat` | minor | New capability in templates or function code |
| `fix` | patch | Bug fix in templates or function code |
| `chore` | none | CI, docs, tooling, tests |
| `build` | none | Dependency bumps |

**Scope** is the component affected: `arm-template`, `bicep-template`, `event-hub`, `blob`, `ci`, etc.

**Breaking change** — add `BREAKING CHANGE:` in the PR description body (it becomes the commit footer after squash):

```
feat(arm-template): drop support for legacy consumption plan

BREAKING CHANGE: scalingMode=Basic is no longer supported
```

Commits within a branch do not need to follow any format — only the PR title matters.

### Feature PR (`feature/fix/chore → develop` or parent feature branch)

**Title:** conventional commit format — e.g. `feat(event-hub): add Flex Consumption support`

Any change to ARM templates must also be made in the equivalent Bicep template, and vice versa.

**Description must include:**
- Jira ticket link
- What changed and why
- Production surfaces affected
- Testing proof

**Approvals:** minimum 2, including one from the tech lead.

CI (lint + unit tests) must pass before review is requested.

Use the [feature PR template](.github/PULL_REQUEST_TEMPLATE/feature_pr.md).

**During review:**
- No force-pushing — reviewer comments become misplaced
- Reviewer comments should be responded to before merge
- New commits are added during review instead of squashing

---

## Testing

### Unit tests

Required for any change to `LogForwarder/`. Run via `npm test`. Tests live in `__tests__/` and run automatically in CI.

Template-only changes do not need unit tests.

### Integration tests

Tests in `test-suite/` invoke the forwarder function locally and verify logs arrive in NRDB. They require real credentials (`LICENSE_KEY`, `LOGS_API`, `ACCOUNT_ID`, `API_KEY`, `NERD_GRAPH_URL`) and are run manually — not yet part of CI.

### Manual testing

Deploy to Azure and verify end-to-end for any template or function code change. Test the hosting plans and network modes affected by the change.

| Hosting plan | `scalingMode` value |
|---|---|
| Consumption | `Basic` |
| Premium | `Enterprise` |
| Flex Consumption | `Flex` |

| Network mode | Description |
|---|---|
| Public | Default, no VNet restrictions |
| Private | VNet-integrated, restricted inbound/outbound |

**Step 1 — Deploy the template**

*ARM template — Azure portal:*
1. Open [Deploy a custom template](https://portal.azure.com/#create/Microsoft.Template)
2. Click "Build your own template in the editor" and paste the ARM template file
3. Fill in the parameters and deploy

*ARM template — CLI:*
```
az deployment group create \
  --resource-group <rg-name> \
  --template-file armTemplates/azuredeploy-blobforwarder.json \
  --parameters newRelicLicenseKey=<key> ...
```

*Bicep template:*
```
az deployment group create \
  --resource-group <rg-name> \
  --template-file bicep/azuredeploy-eventhubforwarder.bicep \
  --parameters newRelicLicenseKey=<key> ...
```

**Step 2 — Override function code (required for function code changes)**

Templates pull from `releases/latest/download/LogForwarder.zip`, not local code. Build and deploy the local zip to the function app after the template deploys:

```
npm run package:logforwarder

az functionapp deployment source config-zip \
  --resource-group <rg-name> \
  --name <function-app-name> \
  --src LogForwarder.zip
```

### Testing proof

Every PR must include screenshots so the reviewer can verify the change was tested end-to-end before approving.

| Change type | Required proof |
|---|---|
| Function code | Azure Function invocation logs + New Relic Logs UI screenshot showing logs received |
| ARM template | Successful deployment output + parameters page screenshot (when params change) + New Relic Logs UI screenshot |
| Bicep template | `az deployment group create` output showing no errors + New Relic Logs UI screenshot |

Include which hosting plan and network mode were tested.

---

## Release

Every `develop → master` merge is a release — template-only changes included.

### Story lifecycle

```
Story created → developed → tested → merged to develop → Done in Jira
```

### Release ticket

Create a release ticket before raising the release PR. It captures:
- All changes going into this release compared to the last release — stories with Jira links and descriptions
- Which production surfaces are being updated
- Manager approval

Non-customer-impacting changes (CI workflow changes, test additions, internal tooling) do not need a release ticket.

### Release readiness

Before raising the release PR:

- [ ] All changes on `develop` have peer and tech lead review
- [ ] No untested changes are on `develop`
- [ ] All stories are linked to the release ticket in Jira
- [ ] Every commit on `develop` since the last release is accounted for — run `git log origin/master..origin/develop --oneline` to check
- [ ] All customer-facing commits use `feat:` or `fix:` prefix — if any are missing, push an empty commit before merging:
  ```
  git commit --allow-empty -m "feat(<scope>): <summary of what this release delivers>"
  git push origin develop
  ```
- [ ] CI is passing on `develop`

### Release timing

Only merge when the release can be monitored for at least two business days after. Postpone if holidays or planned leaves fall in that window.

### Release PR (`develop → master`)

**Title:** `release: <short description>` — e.g. `release: Flex Consumption support and CVE fixes`

**Description must include:**
- Release ticket link
- Stories with Jira links and one-line descriptions
- Production surfaces being updated

**Approvals:** peer and tech lead approval on the PR; manager approval on the release ticket.

**Merge method:** merge commit — not squash. Squash collapses all commits and causes semantic-release to miss version signals from individual `feat:` and `fix:` commits.

Use the [release PR template](.github/PULL_REQUEST_TEMPLATE/release_pr.md).

### What happens automatically on merge to `master`

Semantic-release runs via `release.yml` and:

1. Determines version bump from commits since the last release (`feat:` → minor, `fix:` → patch, `BREAKING CHANGE` → major)
2. Updates `docs/CHANGELOG.md`
3. Bumps version in `package.json`, `package-lock.json`, and `LogForwarder/index.js`
4. Packages `LogForwarder.zip`
5. Creates a GitHub Release with `LogForwarder.zip` and `index.js` as assets
6. Uploads `LogForwarder.zip` and SHA256 checksum to Azure Blob Storage (`nrloggingprodreleases`)

### Post-release

- [ ] Test the integration from the NR integration page in US, EU, and JP regions — confirm logs are flowing to New Relic
- [ ] Close the release ticket with testing proof (screenshots)
- [ ] Sync `develop` with `master` to pick up version bump commits from semantic-release:
  ```
  git checkout develop && git merge origin/master && git push origin develop
  ```
