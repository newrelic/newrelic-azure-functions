# Enhanced Logging with Deployment Context

## Overview

Add deployment metadata to logs so you can easily identify which Azure deployment generated the logs.

This is especially useful when:
- Testing multiple deployments (spike/POC scenarios)
- Running CLI vs Portal deployments side-by-side
- Managing multiple environments (dev, staging, prod)

---

## Changes Required

### 1. Update ARM Template (Add Environment Variables)

**File:** `complete-setup/cli/azuredeploy-vnetflowlogs-complete.json`

Add these environment variables to the Function App configuration (around line 370-440 in the template):

```json
{
  "name": "DEPLOYMENT_CONTEXT_ENABLED",
  "value": "true"
},
{
  "name": "DEPLOYMENT_NAME",
  "value": "[resourceGroup().name]"
},
{
  "name": "DEPLOYMENT_VNET_NAME",
  "value": "[variables('vnetName')]"
},
{
  "name": "DEPLOYMENT_LOCATION",
  "value": "[variables('location')]"
},
{
  "name": "DEPLOYMENT_TYPE",
  "value": "complete-setup"
},
{
  "name": "DEPLOYMENT_METHOD",
  "value": "cli"
}
```

**Full context in template:**
```json
{
  "type": "Microsoft.Web/sites",
  "apiVersion": "2020-12-01",
  "name": "[variables('functionAppName')]",
  "properties": {
    "siteConfig": {
      "appSettings": [
        {
          "name": "EVENTHUB_NAME",
          "value": "[variables('eventHubName')]"
        },
        {
          "name": "EVENTHUB_CONSUMER_CONNECTION",
          "value": "[listKeys(resourceId('Microsoft.EventHub/namespaces/AuthorizationRules', variables('eventHubNamespaceName'), variables('logConsumerAuthorizationRuleName')),'2017-04-01').primaryConnectionString]"
        },
        {
          "name": "EVENTHUB_CONSUMER_GROUP",
          "value": "$Default"
        },
        {
          "name": "NR_LICENSE_KEY",
          "value": "[parameters('newRelicLicenseKey')]"
        },
        {
          "name": "NR_ENDPOINT",
          "value": "[parameters('newRelicEndpoint')]"
        },
        // ⭐ ADD THESE NEW ENVIRONMENT VARIABLES ⭐
        {
          "name": "DEPLOYMENT_CONTEXT_ENABLED",
          "value": "true"
        },
        {
          "name": "DEPLOYMENT_NAME",
          "value": "[resourceGroup().name]"
        },
        {
          "name": "DEPLOYMENT_VNET_NAME",
          "value": "[variables('vnetName')]"
        },
        {
          "name": "DEPLOYMENT_LOCATION",
          "value": "[variables('location')]"
        },
        {
          "name": "DEPLOYMENT_TYPE",
          "value": "complete-setup"
        },
        {
          "name": "DEPLOYMENT_METHOD",
          "value": "cli"
        },
        // ... rest of settings
      ]
    }
  }
}
```

---

### 2. Update LogForwarder Code

**File:** `LogForwarder/index.js`

#### A. Add deployment context constants (after line 23):

```javascript
const NR_MAX_RETRIES = process.env.NR_MAX_RETRIES || 3;
const NR_RETRY_INTERVAL = process.env.NR_RETRY_INTERVAL || 2000; // default: 2 seconds

// ⭐ ADD DEPLOYMENT CONTEXT ⭐
const DEPLOYMENT_CONTEXT_ENABLED = process.env.DEPLOYMENT_CONTEXT_ENABLED === 'true';
const DEPLOYMENT_NAME = process.env.DEPLOYMENT_NAME || 'unknown';
const DEPLOYMENT_VNET_NAME = process.env.DEPLOYMENT_VNET_NAME || 'unknown';
const DEPLOYMENT_LOCATION = process.env.DEPLOYMENT_LOCATION || 'unknown';
const DEPLOYMENT_TYPE = process.env.DEPLOYMENT_TYPE || 'unknown';
const DEPLOYMENT_METHOD = process.env.DEPLOYMENT_METHOD || 'unknown';

function getDeploymentContext() {
  if (!DEPLOYMENT_CONTEXT_ENABLED) {
    return null;
  }
  return {
    deploymentName: DEPLOYMENT_NAME,
    vnetName: DEPLOYMENT_VNET_NAME,
    location: DEPLOYMENT_LOCATION,
    deploymentType: DEPLOYMENT_TYPE,
    deploymentMethod: DEPLOYMENT_METHOD
  };
}
```

#### B. Update VNet Flow Logs handler (replace lines 59-61):

```javascript
async function vnetFlowLogsHandler(messages, context) {
  const deploymentCtx = getDeploymentContext();

  // Enhanced header with deployment context
  context.log('==== VNetFlowLogsForwarder Triggered ====');
  if (deploymentCtx) {
    context.log(`📍 Deployment: ${deploymentCtx.deploymentName}`);
    context.log(`🌐 VNet: ${deploymentCtx.vnetName}`);
    context.log(`📍 Location: ${deploymentCtx.location}`);
    context.log(`🔧 Method: ${deploymentCtx.deploymentMethod}`);
  }
  context.log(`Received ${messages.length} Event Grid event(s)`);

  // ... rest of the function
```

#### C. Update validation log creation (replace lines 105-129):

```javascript
// Create validation log for New Relic
const validationLog = {
  message: 'VNet Flow Logs E2E Validation - Event Received',
  logtype: 'azure.vnet.flowlog.validation',
  validation: {
    status: 'success',
    step: 'event-grid-to-eventhub',
    description: 'Event Grid successfully forwarded blob creation event to Event Hub'
  },
  event: {
    eventType: event.eventType,
    eventTime: event.eventTime,
    subject: event.subject
  },
  blob: {
    url: blobUrl,
    size: blobSize,
    contentType: blobType,
    isPT1HFile: true,
    isFlowLogContainer: blobUrl.includes('insights-logs-flowlogflowevent')
  },
  // ⭐ ADD DEPLOYMENT CONTEXT ⭐
  deployment: deploymentCtx,
  timestamp: new Date().toISOString()
};
```

#### D. Update getCommonAttributes function (replace lines 271-285):

```javascript
function getCommonAttributes(context) {
  const deploymentCtx = getDeploymentContext();

  const attributes = {
    plugin: {
      type: NR_LOGS_SOURCE,
      version: VERSION
    },
    azure: {
      forwardername: context.functionName,
      invocationid: context.invocationId
    },
    tags: getTags()
  };

  // ⭐ ADD DEPLOYMENT CONTEXT TO ALL LOGS ⭐
  if (deploymentCtx) {
    attributes.deployment = deploymentCtx;
  }

  return { attributes };
}
```

---

## Testing the Changes

### 1. Deploy Updated Template

```bash
cd complete-setup/cli/

# The updated template includes deployment context env vars
./deploy-complete.sh bpavan-vnet-logs-cli canadacentral
```

### 2. Deploy Updated Function Code

```bash
cd /Users/bpavan/repos/logint/nr/newrelic-azure-functions

# Make the code changes above to LogForwarder/index.js
# Then package and deploy:

npm run package:logforwarder

FUNCTION_APP=$(az functionapp list \
  --resource-group bpavan-vnet-logs-cli \
  --query "[0].name" -o tsv)

az functionapp deployment source config-zip \
  --resource-group bpavan-vnet-logs-cli \
  --name $FUNCTION_APP \
  --src LogForwarder.zip

az functionapp restart \
  --resource-group bpavan-vnet-logs-cli \
  --name $FUNCTION_APP
```

### 3. Test with Portal Deployment

Now deploy via Portal to see the difference:

```bash
# Portal deployment will have DEPLOYMENT_METHOD=portal
# Resource group: bpavan-vnet-logs-portal
```

In the portal template, set:
```json
{
  "name": "DEPLOYMENT_METHOD",
  "value": "portal"
}
```

---

## What You'll See

### Console Logs (Function App Log Stream)

**Before:**
```
==== VNetFlowLogsForwarder Triggered ====
Received 1 Event Grid event(s)
```

**After:**
```
==== VNetFlowLogsForwarder Triggered ====
📍 Deployment: bpavan-vnet-logs-cli
🌐 VNet: bpavan-vnet
📍 Location: canadacentral
🔧 Method: cli
Received 1 Event Grid event(s)
```

---

### New Relic Query Results

**Query all logs with deployment context:**

```sql
SELECT * FROM Log
WHERE logtype = 'azure.vnet.flowlog.validation'
SINCE 30 minutes ago
```

**Query by specific deployment:**

```sql
SELECT * FROM Log
WHERE deployment.deploymentName = 'bpavan-vnet-logs-cli'
SINCE 30 minutes ago
```

**Compare CLI vs Portal deployments:**

```sql
SELECT
  deployment.deploymentMethod,
  deployment.deploymentName,
  count(*) as EventCount
FROM Log
WHERE logtype = 'azure.vnet.flowlog.validation'
SINCE 1 hour ago
FACET deployment.deploymentMethod
```

**View logs from specific VNet:**

```sql
SELECT * FROM Log
WHERE deployment.vnetName = 'bpavan-vnet'
AND logtype = 'azure.vnet.flowlog'
SINCE 30 minutes ago
```

---

## Example New Relic Log Entry

**With deployment context:**

```json
{
  "message": "VNet Flow Logs E2E Validation - Event Received",
  "logtype": "azure.vnet.flowlog.validation",
  "validation": {
    "status": "success",
    "step": "event-grid-to-eventhub"
  },
  "deployment": {
    "deploymentName": "bpavan-vnet-logs-cli",
    "vnetName": "bpavan-vnet",
    "location": "canadacentral",
    "deploymentType": "complete-setup",
    "deploymentMethod": "cli"
  },
  "blob": {
    "url": "https://bpavan7lk6.blob.core.windows.net/.../PT1H.json",
    "size": 33114,
    "isPT1HFile": true
  },
  "timestamp": "2026-04-28T12:00:00.000Z"
}
```

---

## Benefits

### 1. Easy Identification

```sql
-- Which deployment is working?
SELECT deployment.deploymentName, count(*)
FROM Log
WHERE logtype = 'azure.vnet.flowlog.validation'
FACET deployment.deploymentName
```

### 2. Compare Methods

```sql
-- CLI vs Portal performance
SELECT deployment.deploymentMethod, average(duration)
FROM Log
FACET deployment.deploymentMethod
```

### 3. Environment Tracking

```sql
-- Logs from specific VNet
SELECT * FROM Log
WHERE deployment.vnetName = 'prod-vnet'
```

### 4. Troubleshooting

```sql
-- Find logs from failed deployment
SELECT * FROM Log
WHERE deployment.deploymentName = 'test-deployment-failed'
AND validation.status = 'error'
```

---

## Multiple Deployments Scenario

You can now easily distinguish between multiple test deployments:

**Deployment 1 (CLI):**
- Resource Group: `bpavan-vnet-logs-cli`
- VNet: `bpavan-vnet`
- Method: `cli`

**Deployment 2 (Portal):**
- Resource Group: `bpavan-vnet-logs-portal`
- VNet: `bpavan-vnet`
- Method: `portal`

**Query to compare:**
```sql
SELECT
  deployment.deploymentName,
  deployment.deploymentMethod,
  count(*) as LogCount,
  latest(timestamp) as LastSeen
FROM Log
WHERE logtype = 'azure.vnet.flowlog.validation'
SINCE 1 hour ago
FACET deployment.deploymentName, deployment.deploymentMethod
```

---

## Optional: Add More Context

You can add even more context if needed:

```json
{
  "name": "DEPLOYMENT_OWNER",
  "value": "bpavan"
},
{
  "name": "DEPLOYMENT_PURPOSE",
  "value": "spike-testing"
},
{
  "name": "DEPLOYMENT_CREATED_AT",
  "value": "[utcNow()]"
}
```

Then in the code:
```javascript
const DEPLOYMENT_OWNER = process.env.DEPLOYMENT_OWNER || 'unknown';
const DEPLOYMENT_PURPOSE = process.env.DEPLOYMENT_PURPOSE || 'unknown';
const DEPLOYMENT_CREATED_AT = process.env.DEPLOYMENT_CREATED_AT || 'unknown';
```

---

## Summary

### Changes Required

1. ✅ Add 6 environment variables to ARM template
2. ✅ Add deployment context function to LogForwarder code
3. ✅ Update console logging to show deployment context
4. ✅ Add deployment context to validation logs
5. ✅ Add deployment context to common attributes

### Result

- Console logs show which deployment triggered
- New Relic logs include deployment metadata
- Easy to filter/compare multiple deployments
- Perfect for spike testing multiple scenarios!

---

## Quick Start

**Easiest approach:**

1. I can create a patch file with all the changes
2. You apply the patch
3. Re-deploy function code
4. Done!

Would you like me to:
- [ ] Create the complete modified files ready to use?
- [ ] Create a git patch for easy application?
- [ ] Make the changes directly in your repo?

Let me know and I'll help you implement this! 🚀