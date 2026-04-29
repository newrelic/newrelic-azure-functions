# Test Enhanced Logging with Deployment Context

## ✅ Changes Applied

The following files have been updated with deployment context tracking:

1. **ARM Template:** `arm-templates/complete-setup/cli/azuredeploy-vnetflowlogs-complete.json`
   - Added 6 new environment variables for deployment context

2. **Function Code:** `LogForwarder/index.js`
   - Added deployment context constants and helper function
   - Enhanced console logs with deployment info
   - Added deployment context to validation logs
   - Added deployment context to all New Relic logs

---

## 🚀 Quick Test

### Step 1: Package Updated Function Code

```bash
cd /Users/bpavan/repos/logint/nr/newrelic-azure-functions

# Package the updated code
npm run package:logforwarder
```

### Step 2: Deploy to Existing Function App

```bash
# If you have an existing deployment
FUNCTION_APP=$(az functionapp list \
  --resource-group bpavan-vnet-logs-arm \
  --query "[0].name" -o tsv)

echo "Deploying to: $FUNCTION_APP"

az functionapp deployment source config-zip \
  --resource-group bpavan-vnet-logs-arm \
  --name $FUNCTION_APP \
  --src LogForwarder.zip

# Update app settings with deployment context
az functionapp config appsettings set \
  --resource-group bpavan-vnet-logs-arm \
  --name $FUNCTION_APP \
  --settings \
    DEPLOYMENT_CONTEXT_ENABLED=true \
    DEPLOYMENT_NAME="bpavan-vnet-logs-arm" \
    DEPLOYMENT_VNET_NAME="bpavan-vnet" \
    DEPLOYMENT_LOCATION="canadacentral" \
    DEPLOYMENT_TYPE="complete-setup" \
    DEPLOYMENT_METHOD="cli"

# Restart function app
az functionapp restart \
  --resource-group bpavan-vnet-logs-arm \
  --name $FUNCTION_APP
```

### Step 3: Monitor Logs

```bash
# Watch function logs
az webapp log tail \
  --resource-group bpavan-vnet-logs-arm \
  --name $FUNCTION_APP
```

**Expected output:**
```
==== VNetFlowLogsForwarder Triggered ====
📍 Deployment: bpavan-vnet-logs-arm
🌐 VNet: bpavan-vnet
📍 Location: canadacentral
🔧 Method: cli
Received 1 Event Grid event(s)
```

---

## 🎯 Test Multiple Deployments

### Scenario: Compare CLI vs Portal Deployments

#### Deploy #1: CLI Method

```bash
cd arm-templates/complete-setup/cli/

# Template already has DEPLOYMENT_METHOD=cli
./deploy-complete.sh bpavan-vnet-logs-cli canadacentral

# Deploy function code
cd /Users/bpavan/repos/logint/nr/newrelic-azure-functions
npm run package:logforwarder

FUNCTION_APP=$(az functionapp list \
  --resource-group bpavan-vnet-logs-cli \
  --query "[0].name" -o tsv)

az functionapp deployment source config-zip \
  --resource-group bpavan-vnet-logs-cli \
  --name $FUNCTION_APP \
  --src LogForwarder.zip
```

#### Deploy #2: Portal Method

1. Go to Azure Portal: https://portal.azure.com/#create/Microsoft.Template
2. Load `arm-templates/complete-setup/portal/azuredeploy-vnetflowlogs-complete.json`
3. Fill form with:
   - Resource Group: `bpavan-vnet-logs-portal`
   - Other parameters as needed
4. Deploy
5. Deploy function code with portal-specific settings:

```bash
FUNCTION_APP=$(az functionapp list \
  --resource-group bpavan-vnet-logs-portal \
  --query "[0].name" -o tsv)

# Update deployment method to 'portal'
az functionapp config appsettings set \
  --resource-group bpavan-vnet-logs-portal \
  --name $FUNCTION_APP \
  --settings DEPLOYMENT_METHOD=portal

az functionapp deployment source config-zip \
  --resource-group bpavan-vnet-logs-portal \
  --name $FUNCTION_APP \
  --src LogForwarder.zip
```

---

## 🔍 Verify in New Relic

### Query All Deployments

```sql
SELECT * FROM Log
WHERE logtype = 'azure.vnet.flowlog.validation'
SINCE 30 minutes ago
```

**Expected fields:**
```json
{
  "deployment.deploymentName": "bpavan-vnet-logs-cli",
  "deployment.vnetName": "bpavan-vnet",
  "deployment.location": "canadacentral",
  "deployment.deploymentType": "complete-setup",
  "deployment.deploymentMethod": "cli"
}
```

### Compare CLI vs Portal

```sql
SELECT
  deployment.deploymentMethod,
  deployment.deploymentName,
  count(*) as EventCount,
  latest(timestamp) as LastSeen
FROM Log
WHERE logtype = 'azure.vnet.flowlog.validation'
SINCE 1 hour ago
FACET deployment.deploymentMethod
```

**Expected result:**
```
deploymentMethod | deploymentName           | EventCount | LastSeen
-----------------|--------------------------|------------|------------------
cli              | bpavan-vnet-logs-cli     | 5          | 2026-04-28 12:30
portal           | bpavan-vnet-logs-portal  | 3          | 2026-04-28 12:25
```

### Filter by Specific Deployment

```sql
SELECT * FROM Log
WHERE deployment.deploymentName = 'bpavan-vnet-logs-cli'
AND logtype = 'azure.vnet.flowlog.validation'
SINCE 1 hour ago
```

### Filter by VNet Name

```sql
SELECT * FROM Log
WHERE deployment.vnetName = 'bpavan-vnet'
SINCE 1 hour ago
```

---

## 📊 Example Log Output

### Console Logs (Azure Portal / CLI)

**Before Enhancement:**
```
2026-04-28T12:00:00.000Z [Information] ==== VNetFlowLogsForwarder Triggered ====
2026-04-28T12:00:00.100Z [Information] Received 1 Event Grid event(s)
2026-04-28T12:00:00.200Z [Information] Event Type: Microsoft.Storage.BlobCreated
2026-04-28T12:00:00.300Z [Information] ✓ VALIDATED: This is a VNet Flow Log file
```

**After Enhancement:**
```
2026-04-28T12:00:00.000Z [Information] ==== VNetFlowLogsForwarder Triggered ====
2026-04-28T12:00:00.010Z [Information] 📍 Deployment: bpavan-vnet-logs-cli
2026-04-28T12:00:00.020Z [Information] 🌐 VNet: bpavan-vnet
2026-04-28T12:00:00.030Z [Information] 📍 Location: canadacentral
2026-04-28T12:00:00.040Z [Information] 🔧 Method: cli
2026-04-28T12:00:00.100Z [Information] Received 1 Event Grid event(s)
2026-04-28T12:00:00.200Z [Information] Event Type: Microsoft.Storage.BlobCreated
2026-04-28T12:00:00.300Z [Information] ✓ VALIDATED: This is a VNet Flow Log file
```

### New Relic Log Entry

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
  "attributes": {
    "plugin": {
      "type": "azure",
      "version": "0.0.0-development"
    },
    "azure": {
      "forwardername": "VNetFlowLogsForwarder",
      "invocationid": "abc-123-def"
    },
    "deployment": {
      "deploymentName": "bpavan-vnet-logs-cli",
      "vnetName": "bpavan-vnet",
      "location": "canadacentral",
      "deploymentType": "complete-setup",
      "deploymentMethod": "cli"
    }
  },
  "timestamp": "2026-04-28T12:00:00.000Z"
}
```

---

## 🎓 Use Cases

### 1. Identify Which Deployment is Working

Problem: "I have 3 test deployments. Which one is successfully forwarding logs?"

Solution:
```sql
SELECT
  deployment.deploymentName,
  count(*) as SuccessfulForwards
FROM Log
WHERE logtype = 'azure.vnet.flowlog.validation'
AND validation.status = 'success'
SINCE 1 hour ago
FACET deployment.deploymentName
ORDER BY SuccessfulForwards DESC
```

### 2. Compare Performance

Problem: "Is CLI deployment faster than Portal deployment?"

Solution:
```sql
SELECT
  deployment.deploymentMethod,
  average(duration) as AvgProcessingTime,
  percentile(duration, 95) as P95ProcessingTime
FROM Log
WHERE logtype = 'azure.vnet.flowlog'
SINCE 1 hour ago
FACET deployment.deploymentMethod
```

### 3. Troubleshoot Specific Deployment

Problem: "The portal deployment isn't working. Show me all its logs."

Solution:
```sql
SELECT * FROM Log
WHERE deployment.deploymentMethod = 'portal'
SINCE 1 hour ago
ORDER BY timestamp DESC
```

### 4. Track Multiple VNets

Problem: "I have multiple VNets being monitored. Show logs from prod VNet only."

Solution:
```sql
SELECT * FROM Log
WHERE deployment.vnetName = 'prod-vnet'
SINCE 1 hour ago
```

---

## 🔧 Troubleshooting

### No Deployment Context in Logs

**Check environment variables:**
```bash
az functionapp config appsettings list \
  --resource-group YOUR_RG \
  --name YOUR_FUNCTION_APP \
  --query "[?starts_with(name, 'DEPLOYMENT')].{Name:name, Value:value}" \
  --output table
```

**Expected output:**
```
Name                         Value
---------------------------  ---------------------
DEPLOYMENT_CONTEXT_ENABLED   true
DEPLOYMENT_NAME              bpavan-vnet-logs-cli
DEPLOYMENT_VNET_NAME         bpavan-vnet
DEPLOYMENT_LOCATION          canadacentral
DEPLOYMENT_TYPE              complete-setup
DEPLOYMENT_METHOD            cli
```

**If missing, add them:**
```bash
az functionapp config appsettings set \
  --resource-group YOUR_RG \
  --name YOUR_FUNCTION_APP \
  --settings \
    DEPLOYMENT_CONTEXT_ENABLED=true \
    DEPLOYMENT_NAME="YOUR_RG_NAME" \
    DEPLOYMENT_VNET_NAME="YOUR_VNET" \
    DEPLOYMENT_LOCATION="canadacentral" \
    DEPLOYMENT_TYPE="complete-setup" \
    DEPLOYMENT_METHOD="cli"

az functionapp restart --resource-group YOUR_RG --name YOUR_FUNCTION_APP
```

### Logs Show "unknown" Values

This means the environment variables aren't set or function code isn't updated.

**Fix:**
1. Re-deploy function code
2. Check environment variables
3. Restart function app

---

## ✅ Success Checklist

- [ ] ARM template updated with deployment context env vars
- [ ] Function code updated with deployment context logic
- [ ] Function code packaged: `npm run package:logforwarder`
- [ ] Function code deployed to Azure
- [ ] Environment variables configured in Function App
- [ ] Function App restarted
- [ ] Console logs show deployment context (📍 🌐 🔧 emojis)
- [ ] New Relic logs include `deployment.*` fields
- [ ] Can filter logs by `deployment.deploymentName`

---

## 🎉 Summary

**What You Gain:**

1. ✅ **Easy Identification** - Know which deployment generated each log
2. ✅ **Multi-Deployment Testing** - Compare CLI vs Portal side-by-side
3. ✅ **Troubleshooting** - Filter logs by deployment name
4. ✅ **Environment Tracking** - Separate dev/staging/prod logs
5. ✅ **Better Observability** - Deployment metadata in every log

**Query Examples:**

```sql
-- All logs from CLI deployments
WHERE deployment.deploymentMethod = 'cli'

-- Logs from specific resource group
WHERE deployment.deploymentName = 'bpavan-vnet-logs-cli'

-- Logs from specific VNet
WHERE deployment.vnetName = 'bpavan-vnet'

-- Logs from specific region
WHERE deployment.location = 'canadacentral'
```

---

Happy testing! 🚀

Your logs now include full deployment context for easy identification and filtering!