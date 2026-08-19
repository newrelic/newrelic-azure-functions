# Testing Guide

All changes should be tested before the PR is raised. CI (lint + unit tests) is a gate, not a substitute for manual testing.

---

## Unit Tests

Unit tests are needed for any change to `LogForwarder/`. Tests run via `npm test`.

- New behavior needs test coverage
- Existing tests should continue to pass
- Coverage regressions should be explained in the PR

Template-only changes do not need unit tests but still need manual testing.

---

## Manual Testing

### Test matrix

Every change should be verified across the relevant hosting plans and network modes:

| Hosting plan | `scalingMode` value |
|---|---|
| Consumption | `Basic` |
| Premium | `Enterprise` |
| Flex Consumption | `Flex` |

| Network mode | Description |
|---|---|
| Public | Default, no VNet restrictions |
| Private | VNet-integrated, restricted inbound/outbound |

Not every change requires the full matrix — test the plans and modes that are affected by the change. Document which combinations were tested in the PR.

### What to verify per scenario

For each combination tested:
1. Template deploys successfully with no errors
2. Function app is created and running
3. Configuration (app settings, connection strings) is correct in the Azure portal
4. Function is triggered (upload a blob or send an Event Hub message)
5. Logs appear in New Relic Logs UI with correct attributes

### Deploying the template

**ARM template — Azure portal (UI):**
1. Open [Deploy a custom template](https://portal.azure.com/#create/Microsoft.Template)
2. Click "Build your own template in the editor" and paste the contents of the ARM template file
3. Fill in the parameters and deploy
4. Screenshot the parameters page before deploying — required as testing proof when template parameters are added, changed, or removed

**ARM template — CLI:**
```
az deployment group create \
  --resource-group <rg-name> \
  --template-file armTemplates/azuredeploy-blobforwarder.json \
  --parameters newRelicLicenseKey=<key> ...
```

**Bicep template:**
```
az deployment group create \
  --resource-group <rg-name> \
  --template-file bicep/azuredeploy-eventhubforwarder.bicep \
  --parameters newRelicLicenseKey=<key> ...
```

### Deploying local function code for testing

Templates reference `releases/latest/download/LogForwarder.zip` — this pulls the last published release, not the local changes being tested. To test local code changes, override the function app deployment after the template deploy:

```
# Package the local build
npm run package:logforwarder

# Deploy the local zip to the function app
az functionapp deployment source config-zip \
  --resource-group <rg-name> \
  --name <function-app-name> \
  --src LogForwarder.zip
```

This replaces the release artifact on the function app without affecting the template.

---

## Testing Proof

Testing proof is attached to the PR description so reviewers can verify the change was tested end-to-end.

For **function code changes:**
- Azure Function invocation logs showing successful execution
- New Relic Logs UI screenshot showing logs received with correct attributes

For **ARM template changes:**
- Screenshot of the parameters page in Azure portal (required when parameters are added, changed, or removed)
- Azure portal deployment output showing no errors
- New Relic Logs UI screenshot confirming end-to-end flow

For **Bicep template changes:**
- `az deployment group create` CLI output showing no errors
- New Relic Logs UI screenshot confirming end-to-end flow

Good proof shows the specific scenario tested — hosting plan, network mode, and a result (logs in New Relic) that confirms it was a live test run.
