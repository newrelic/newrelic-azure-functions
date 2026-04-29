# VNet Flow Logs E2E Validation Function

## Overview

I've created a simple validation function that proves the E2E flow from Event Grid → Event Hub → Function App → New Relic is working.

## What the Function Does

1. **Triggers** on Event Hub messages (which contain Event Grid events about blob creation)
2. **Logs** detailed information about each event to the Function App logs
3. **Validates** that the event is for a PT1H.json file (VNet Flow Log)
4. **Forwards** a validation log message to New Relic with event details

## Function Code Location

```
/Users/bpavan/repos/logint/nr/newrelic-azure-functions/VNetFlowLogsValidator/index.js
```

## Deployment Package Created

```
/Users/bpavan/repos/logint/nr/newrelic-azure-functions/VNetFlowLogsValidator.zip (214 KB)
```

## Deployment Instructions

### Option 1: Azure Portal (Recommended for quick testing)

1. **Go to Azure Portal** → Function Apps → `bpavan-vnet-func`

2. **Navigate to Deployment Center**
   - Click "Deployment Center" in the left menu

3. **Upload Zip File**
   - Select "External Git" or "Local Git" as source
   - OR use "Advanced tools (Kudu)" → Click "Go" → Debug console → CMD
   - Drag and drop `VNetFlowLogsValidator.zip` to `/home/site/wwwroot`
   - Extract: `unzip VNetFlowLogsValidator.zip`

### Option 2: Azure CLI (if SSL issues resolved)

```bash
FUNCTION_APP="bpavan-vnet-func"
TEST_RG="bpavan-vnet-logs"

az functionapp deployment source config-zip \
  --resource-group $TEST_RG \
  --name $FUNCTION_APP \
  --src /Users/bpavan/repos/logint/nr/newrelic-azure-functions/VNetFlowLogsValidator.zip
```

### Option 3: VS Code Azure Functions Extension

1. Install Azure Functions extension in VS Code
2. Open the repo folder in VS Code
3. Right-click on `VNetFlowLogsValidator` folder
4. Select "Deploy to Function App..."
5. Choose `bpavan-vnet-func`

### Option 4: Manual File Upload via Azure Portal

1. Go to Function App → **Development Tools** → **App Service Editor** → Click "Go"
2. Create folder `VNetFlowLogsValidator`
3. Copy the content of `VNetFlowLogsValidator/index.js` into a new file in that folder
4. Restart the Function App

## Configuration Already Set

Your Function App already has all the required environment variables:

```
✓ EVENTHUB_NAME = bpavan-vnet-eventhub
✓ EVENTHUB_CONSUMER_CONNECTION = [configured]
✓ EVENTHUB_CONSUMER_GROUP = vnetflowlogs-consumer
✓ NR_LICENSE_KEY = d377ad18ef50****** [configured]
✓ NR_ENDPOINT = https://log-api.newrelic.com/log/v1 [default]
✓ VNETFLOWLOGS_FORWARDER_ENABLED = true
```

The function will automatically activate once deployed because `VNETFLOWLOGS_FORWARDER_ENABLED=true`.

## What the Function Logs

### Console Logs (Azure Portal → Log Stream)

You'll see output like this:

```
==== VNetFlowLogsValidator Triggered ====
Received 1 Event Grid event(s)

--- Processing Event 1/1 ---
Event Type: Microsoft.Storage.BlobCreated
Event Subject: /blobServices/default/containers/insights-logs-flowlogflowevent/blobs/...PT1H.json
Event Time: 2026-04-24T05:22:00.0000000Z
Blob URL: https://bpavanvnetlogstorage.blob.core.windows.net/.../PT1H.json
Blob Size: 95432 bytes
Blob Type: application/json
✓ VALIDATED: This is a VNet Flow Log file (PT1H.json)
✓ Event Grid → Event Hub flow is working!
✓ Validation log prepared for New Relic

==== Sending 1 validation log(s) to New Relic ====
New Relic response: 202
✓ Successfully sent validation logs to New Relic

==== VNetFlowLogsValidator Completed ====
```

### New Relic Logs

The function sends validation logs to New Relic with this structure:

```json
{
  "message": "VNet Flow Logs E2E Validation - Event Received",
  "logtype": "azure.vnet.flowlog.validation",
  "validation": {
    "status": "success",
    "step": "event-grid-to-eventhub",
    "description": "Event Grid successfully forwarded blob creation event to Event Hub"
  },
  "event": {
    "eventType": "Microsoft.Storage.BlobCreated",
    "eventTime": "2026-04-24T05:22:00.0000000Z",
    "subject": "/blobServices/default/containers/.../PT1H.json"
  },
  "blob": {
    "url": "https://bpavanvnetlogstorage.blob.core.windows.net/.../PT1H.json",
    "size": 95432,
    "contentType": "application/json",
    "isPT1HFile": true,
    "isFlowLogContainer": true
  },
  "timestamp": "2026-04-24T05:22:15.123Z"
}
```

## Verification Steps

### 1. Verify Function is Deployed

```bash
FUNCTION_APP="bpavan-vnet-func"
TEST_RG="bpavan-vnet-logs"

az functionapp function list \
  --name $FUNCTION_APP \
  --resource-group $TEST_RG \
  --output table
```

**Expected**: Should show `VNetFlowLogsValidator` in the list.

### 2. View Function Logs in Real-Time

**Azure Portal**:
1. Go to Function Apps → `bpavan-vnet-func`
2. Click "Log stream" (left menu under Monitoring)
3. Watch for incoming events

**Azure CLI**:
```bash
az webapp log tail \
  --name bpavan-vnet-func \
  --resource-group bpavan-vnet-logs
```

### 3. Trigger a Test Event

Upload a test blob to trigger the flow:

```bash
SOURCE_STORAGE="bpavanvnetlogstorage"

cat > /tmp/test-validation.json <<'EOF'
{
  "records": [{
    "time": "2026-04-24T10:00:00.000Z",
    "macAddress": "00-0D-3A-VALIDATION-TEST",
    "flows": [{"rule": "TestRule", "flows": []}]
  }]
}
EOF

az storage blob upload \
  --account-name $SOURCE_STORAGE \
  --container-name insights-logs-flowlogflowevent \
  --name "resourceId=/test/validation/PT1H.json" \
  --file /tmp/test-validation.json \
  --auth-mode key \
  --overwrite
```

**Expected**:
- Within 1-2 minutes, Event Grid detects the blob
- Event Grid sends event to Event Hub
- Function triggers and processes the event
- Logs appear in Log Stream
- Validation log sent to New Relic

### 4. Query New Relic for Validation Logs

**New Relic Query**:
```sql
SELECT * FROM Log
WHERE logtype = 'azure.vnet.flowlog.validation'
SINCE 1 hour ago
```

**Expected Fields**:
- `message`: "VNet Flow Logs E2E Validation - Event Received"
- `validation.status`: "success"
- `blob.isPT1HFile`: true
- `blob.isFlowLogContainer`: true
- `event.eventType`: "Microsoft.Storage.BlobCreated"

## Next Steps After Deployment

Once the function is deployed:

1. **Watch the logs** for incoming events (existing PT1H.json files will continue to update)
2. **Upload a test blob** to trigger an event manually
3. **Check New Relic** for validation logs
4. **Verify E2E flow** is working

## Important Notes

### Current Function App Settings

The function will work immediately after deployment because:
- ✅ Event Hub connection is already configured
- ✅ New Relic license key is already configured
- ✅ VNETFLOWLOGS_FORWARDER_ENABLED is already set to true
- ✅ Event Hub consumer group is configured

### This is a VALIDATION Function

This function is for **validation only**. It does NOT:
- Read blob contents (no Storage permissions needed yet)
- Implement delta extraction
- Handle state management
- Parse actual flow log data

It only:
- Receives Event Grid events from Event Hub
- Logs event details
- Sends validation logs to New Relic

### Storage Permissions

For this validation function, you **DO NOT need** Storage Blob Data Reader permissions yet because:
- It only reads Event Grid event metadata
- It does NOT download or read the actual blob contents

Storage permissions will be needed when you implement the full forwarder that reads and processes PT1H.json files.

## Success Criteria

✅ E2E validation is successful if:

1. **Function deploys** without errors
2. **Function triggers** when PT1H.json files are created/updated
3. **Function logs** show event details in Log Stream
4. **New Relic receives** validation logs with `logtype: azure.vnet.flowlog.validation`
5. **No errors** in function execution logs

## Troubleshooting

### Function Not Triggering

**Check**:
```bash
# Verify Event Hub is receiving messages
az monitor metrics list \
  --resource-group bpavan-vnet-logs \
  --resource bpavan-vnet-eventhub-ns \
  --resource-type "Microsoft.EventHub/namespaces" \
  --metric "IncomingMessages" \
  --start-time "$(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ)" \
  --interval PT5M
```

### Function Triggering But Not Logging

**Check**:
- Application Insights connection
- Log level configuration
- Function App restart may be needed

### Logs Not Appearing in New Relic

**Check**:
- NR_LICENSE_KEY is correct
- NR_ENDPOINT is correct (US: log-api.newrelic.com, EU: log-api.eu.newrelic.com)
- Function logs show "New Relic response: 202"
- Network connectivity from Function App to New Relic

## Deployment Package Contents

The `VNetFlowLogsValidator.zip` contains:

```
VNetFlowLogsValidator/
  └── index.js          # Validation function code
LogForwarder/
  └── index.js          # Existing log forwarder (unchanged)
host.json               # Function app host configuration
package.json            # Dependencies
node_modules/
  └── @azure/functions/ # Azure Functions SDK
```

## Function Registration

The function registers itself using the Azure Functions v4 programming model:

```javascript
app.eventHub('VNetFlowLogsValidator', {
  eventHubName: process.env.EVENTHUB_NAME,
  connection: 'EVENTHUB_CONSUMER_CONNECTION',
  cardinality: 'many',
  consumerGroup: process.env.EVENTHUB_CONSUMER_GROUP || '$Default',
  handler: async (messages, context) => {
    // Process Event Grid events
  },
});
```

This automatically creates an Event Hub trigger when the function app starts.

---

## Quick Deploy Command (if you have Azure CLI without SSL issues)

```bash
cd /Users/bpavan/repos/logint/nr/newrelic-azure-functions

az functionapp deployment source config-zip \
  --resource-group bpavan-vnet-logs \
  --name bpavan-vnet-func \
  --src VNetFlowLogsValidator.zip
```

---

## Contact

If deployment fails or you need help, check:
1. Function App logs: Azure Portal → Log Stream
2. Application Insights: Azure Portal → Application Insights → Live Metrics
3. Deployment logs: Azure Portal → Deployment Center → Logs