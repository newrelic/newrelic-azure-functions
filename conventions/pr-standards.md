# PR Standards

Two types of PRs exist in this repo with different requirements.

---

## Feature PR (`feature/fix/chore → develop`)

**Title:** conventional commit format (e.g. `feat(event-hub): add Flex Consumption support`)

**Description must include:**
- Jira ticket link (`NR-XXXXX`)
- What changed and why
- Which production surfaces are affected (ARM templates / Bicep templates / function code)
- Testing proof (see [Testing Guide](./testing-guide.md))

**CI checks:** lint and unit tests must pass before review is requested.

**Approvals needed:** minimum 2, including one from the tech lead.

---

## Release PR (`develop → master`)

**Title:** `release: <short description>` (e.g. `release: Flex Consumption support and CVE fixes`)

**Description must include:**
- Release ticket link (`NR-XXXXX`)
- List of stories included with Jira links
- Which production surfaces are being updated

**CI checks:** lint and unit tests must pass before merge.

**Approvals needed:** approval from the tech lead on the PR, and approval from the manager on the release ticket.

Merged using a **merge commit** — not squash. See [Release Process](./release-process.md) for why.

---

## General

- No force-pushing during an active review — reviewer comments become misplaced
- Reviewer comments should be responded to (addressed or discussed) before the PR is merged
- New commits are added during review instead of squashing
