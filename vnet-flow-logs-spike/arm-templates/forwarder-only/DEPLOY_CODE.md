# Deploying Local Function Code After ARM Template

After the ARM template creates your infrastructure, you need to deploy your local LogForwarder code that includes the VNetFlowLogsForwarder.

## Prerequisites

✅ ARM template deployment completed successfully
✅ Function App created (e.g., `nrlogs-vnetflowlogsforwarder-xxxxx`)
✅ LogForwarder.zip package created locally

## Step 1: Package Your Code

From the repository root:

```bash
cd /Users/bpavan/repos/logint/nr/newrelic-azure-functions

# Create the deployment package
npm run package:logforwarder

# Verify the package was created
ls -lh LogForwarder.zip
```

**Expected output:** `LogForwarder.zip` (around 215 KB)

## Step 2: Deploy Code to Function App

### Option A: Azure Portal (Easy)

1. Navigate to Azure Portal → Your Function App
2. Go to **Deployment Center**
3. Choose **Publish Files**
4. Upload `LogForwarder.zip`
5. Click **Sync** or **Restart** the function app

### Option B: Azure CLI (Recommended)

```bash
# Set your function app name (from ARM template deployment output)
FUNCTION_APP_NAME="nrlogs-vnetflowlogsforwarder-xxxxx"
RESOURCE_GROUP="bpavan-vnet-logs-arm"

# Deploy the zip file
az functionapp deployment source config-zip \
  --resource-group $RESOURCE_GROUP \
  --name $FUNCTION_APP_NAME \
  --src LogForwarder.zip

# Restart the function app
az functionapp restart \
  --resource-group $RESOURCE_GROUP \
  --name $FUNCTION_APP_NAME
```

### Option C: Azure PowerShell

```powershell
$FunctionAppName = "nrlogs-vnetflowlogsforwarder-xxxxx"
$ResourceGroup = "bpavan-vnet-logs-arm"
$ZipPath = "LogForwarder.zip"

# Deploy the zip file
Publish-AzWebApp `
  -ResourceGroupName $ResourceGroup `
  -Name $FunctionAppName `
  -ArchivePath $ZipPath `
  -Force

# Restart the function app
Restart-AzWebApp `
  -ResourceGroupName $ResourceGroup `
  -Name $FunctionAppName
```

## Step 3: Verify Deployment

### Check Functions List

```bash
az functionapp function list \
  --resource-group $RESOURCE_GROUP \
  --name $FUNCTION_APP_NAME \
  --output table
```

**Expected output:**
```
Name
------------------------
VNetFlowLogsForwarder
```

### Check Function Logs

```bash
az webapp log tail \
  --resource-group $RESOURCE_GROUP \
  --name $FUNCTION_APP_NAME
```

**Wait for PT1H.json file updates (happens every ~60 seconds), then you should see:**
```
==== VNetFlowLogsForwarder Triggered ====
Received 1 Event Grid event(s)
Event Type: Microsoft.Storage.BlobCreated
Blob URL: .../PT1H.json
✓ VALIDATED: This is a VNet Flow Log file (PT1H.json)
Got response:202
Logs payload successfully sent to New Relic.
```

## Step 4: Verify in New Relic

Log in to New Relic and run:

```sql
SELECT * FROM Log
WHERE logtype = 'azure.vnet.flowlog.validation'
SINCE 15 minutes ago
ORDER BY timestamp DESC
```

## Troubleshooting

### Issue: Package too large

If you get "Package size exceeds limit" error:

```bash
# Remove development dependencies
cd /Users/bpavan/repos/logint/nr/newrelic-azure-functions
npm ci --omit=dev

# Re-package
npm run package:logforwarder
```

### Issue: Function not appearing

The function might not be registered. Check the environment variable:

```bash
az functionapp config appsettings list \
  --resource-group $RESOURCE_GROUP \
  --name $FUNCTION_APP_NAME \
  --query "[?name=='VNETFLOWLOGS_FORWARDER_ENABLED']"
```

Should show: `"value": "true"`

### Issue: Deployment hangs or fails

Try using the Azure Portal method (Deployment Center → Publish Files) which is more reliable for manual uploads.

## Complete Deployment Flow

Here's the complete sequence after ARM template deployment:

```bash
# 1. Navigate to repo
cd /Users/bpavan/repos/logint/nr/newrelic-azure-functions

# 2. Package code
npm run package:logforwarder

# 3. Get function app name from deployment
FUNCTION_APP_NAME=$(az functionapp list \
  --resource-group bpavan-vnet-logs-arm \
  --query "[0].name" \
  --output tsv)

echo "Deploying to: $FUNCTION_APP_NAME"

# 4. Deploy code
az functionapp deployment source config-zip \
  --resource-group bpavan-vnet-logs-arm \
  --name $FUNCTION_APP_NAME \
  --src LogForwarder.zip

# 5. Restart function app
az functionapp restart \
  --resource-group bpavan-vnet-logs-arm \
  --name $FUNCTION_APP_NAME

# 6. Monitor logs
echo "Waiting 10 seconds for restart..."
sleep 10

az webapp log tail \
  --resource-group bpavan-vnet-logs-arm \
  --name $FUNCTION_APP_NAME
```

**Total time:** ~2-3 minutes

---

**Next:** After code deployment, verify logs are flowing to New Relic!