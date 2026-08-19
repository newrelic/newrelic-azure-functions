# Known Gaps & Manual Steps

Current automation gaps and the manual steps needed until they are addressed.

---

## No Branch Protection Enforcement

GitHub branch protection is not configured to enforce minimum approvals or block direct commits to `develop` and `master`. A PR can currently be merged with a single approval, and a direct push to `master` can trigger an unintended release.

**Manual step:** Approval requirements in [PR Standards](./pr-standards.md) are followed by the team manually.

---

## No Release Ticket Gate

There is no automated check that a release ticket is linked before the release PR is merged. The PR author should verify the release ticket is linked and manager-approved before requesting the merge.

---

## No Integration or E2E Tests

CI only runs lint and unit tests. There are no automated tests that deploy to Azure or verify logs reach New Relic. Manual end-to-end testing in a real Azure environment is required on every PR — see [Testing Guide](./testing-guide.md).

---

## No Commit Prefix Enforcement

There is no check preventing a customer-facing change from being committed as `chore:`, which would skip the release. The commit prefix on every PR should be verified against the change type during review — see [Branching & Commit Standards](./branching-and-commits.md).

---

## Templates Are Not Independently Versioned

ARM and Bicep templates do not carry their own version number. Customers cannot pin to a specific template version — they always get `master` or `releases/latest`. This is a known limitation to be addressed in a future improvement.
