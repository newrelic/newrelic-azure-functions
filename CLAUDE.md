# Engineering Standards — newrelic-azure-functions

Single source of truth for engineering process on this repo. All contributors are expected to follow these standards at every phase of the SDLC.

Detailed guides live in [`conventions/`](./conventions/).

---

## Project Overview

This repo contains Azure Functions that collect and forward logs from Microsoft Azure to the New Relic Logs API:

- **Blob Forwarder** — triggered by new blobs in Azure Blob Storage
- **Event Hub Forwarder** — triggered by messages on an Azure Event Hub

### Production Surfaces

Three independent surfaces go live as soon as a change reaches `master` — there is no staging buffer.

| Surface | Files | Affected customers |
|---|---|---|
| ARM templates | `armTemplates/azuredeploy-*.json` | Deploying via "Deploy to Azure" button |
| Bicep templates | `bicep/azuredeploy-*.bicep` | Deploying via Bicep CLI |
| Function code | `LogForwarder/` | Fresh installs and redeployments |

Both ARM and Bicep templates reference `releases/latest/download/LogForwarder.zip` — a new GitHub Release instantly changes what all three surfaces deliver to customers.

> Before merging to `master`: is this ready to be live in production right now?

---

## Key Rules at a Glance

| Rule | Detail |
|---|---|
| Every customer-facing change uses `feat:` or `fix:` | Using `chore:` on templates or function code skips the release |
| Every `develop → master` merge is a release | No exceptions — template-only changes are also releases |
| Release ticket required before release PR | Covers all stories going out, approved by manager |
| Two approvals needed on feature PRs | Including one from the tech lead |
| Release PR uses merge commit, not squash | Squash breaks semantic-release version calculation |
| Testing proof required on every PR | Screenshots, logs, CLI output — see testing guide |

---

## Conventions

- [Branching & Commit Standards](./conventions/branching-and-commits.md)
- [PR Standards](./conventions/pr-standards.md)
- [Testing Guide](./conventions/testing-guide.md)
- [Release Process](./conventions/release-process.md)
- [Known Gaps & Manual Steps](./conventions/known-gaps.md)
