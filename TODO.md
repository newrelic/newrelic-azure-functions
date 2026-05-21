# Follow-up TODOs

Items deferred from PR #137 (VNet Flow Logs Forwarder), to be addressed in separate PRs.

## 1. Monorepo refactor: independent release per forwarder

Convert the repo to npm workspaces so each forwarder ships independently.

- Per-workspace `package.json` (correct V4 `main` entry point per forwarder)
- Per-workspace `host.json` (each forwarder owns its own runtime config)
- Per-workspace `.releaserc.json` with `tagFormat`:
  - `logforwarder-v${version}`
  - `vnetflow-v${version}`
- Conventional-commit scopes drive which forwarder bumps:
  - `feat(logforwarder): ...` → bumps LogForwarder only
  - `feat(vnetflow): ...` → bumps VNetFlowForwarder only
- Matrix-strategy GitHub Actions workflow runs `semantic-release` once per workspace
- Separate changelogs: `docs/CHANGELOG-LogForwarder.md`, `docs/CHANGELOG-VNetFlow.md`
- Adding a new forwarder = drop-in workspace folder + 1 line in CI matrix

## 2. VNetFlow cursor cleanup strategy

Cursor rows in Azure Table Storage accumulate over time (one per hourly PT1H.json blob).

- Add a timer-triggered Azure Function in the VNetFlowForwarder app
- New env var: `CURSOR_RETENTION_DAYS` (default `7`)
- On schedule (e.g. daily), delete rows where `updatedAt` is older than retention window
- Add unit tests for the cleanup loop
- Document the retention default in the README
