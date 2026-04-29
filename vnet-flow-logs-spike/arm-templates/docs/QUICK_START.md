# VNet Flow Logs ARM Deployment - Quick Start

Complete workflow to deploy VNet Flow Logs forwarder using ARM template with manual code deployment.

## 🚀 Step-by-Step Deployment

### Step 1: Deploy Infrastructure (5-10 minutes)

```bash
cd /Users/bpavan/repos/logint/nr/newrelic-azure-functions/vnet-flow-logs-spike

# Run automated deployment
./deploy.sh bpavan-vnet-logs-arm canadacentral
```

**What happens:**
- ✅ Creates resource group
- ✅ Validates ARM template
- ✅ Shows what-if analysis
- ✅ Deploys infrastructure (Event Grid, Event Hub, Function App, etc.)
- ⚠️  Does NOT deploy function code (you'll do this manually)

**Expected output at the end:**
```
Function App Name: nrlogs-vnetflowlogsforwarder-xxxxx
Managed Identity Principal ID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

---

### Step 2: Grant Storage Permissions (1 minute)

Copy the command shown by the deployment script and run it:

```bash
# Example (use the actual values from your deployment output)
PRINCIPAL_ID="your-principal-id-from-step-1"

SOURCE_STORAGE_ACCOUNT=$(az storage account show \
  --name bpavanvnetlogstorage \
  --resource-group bpavan-vnet-logs \
  --query id \
  --output tsv)

az role assignment create \
  --assignee $PRINCIPAL_ID \
  --role "Storage Blob Data Reader" \
  --scope $SOURCE_STORAGE_ACCOUNT
```

✅ **Checkpoint:** Function App can now read from source storage

---

### Step 3: Deploy Function Code (2-3 minutes)

```bash
cd /Users/bpavan/repos/logint/nr/newrelic-azure-functions

# Package your code
npm run package:logforwarder

# Get function app name
FUNCTION_APP_NAME=$(az functionapp list \
  --resource-group bpavan-vnet-logs-arm \
  --query "[0].name" \
  --output tsv)

echo "Deploying to: $FUNCTION_APP_NAME"

# Deploy the package
az functionapp deployment source config-zip \
  --resource-group bpavan-vnet-logs-arm \
  --name $FUNCTION_APP_NAME \
  --src LogForwarder.zip

# Restart to ensure changes take effect
az functionapp restart \
  --resource-group bpavan-vnet-logs-arm \
  --name $FUNCTION_APP_NAME
```

✅ **Checkpoint:** Function code is deployed with VNetFlowLogsForwarder

---

### Step 4: Verify Deployment (2-3 minutes)

#### Check function is registered:

```bash
az functionapp function list \
  --resource-group bpavan-vnet-logs-arm \
  --name $FUNCTION_APP_NAME \
  --output table
```

**Expected:**
```
Name
------------------------
VNetFlowLogsForwarder
```

#### Monitor live logs:

```bash
az webapp log tail \
  --resource-group bpavan-vnet-logs-arm \
  --name $FUNCTION_APP_NAME
```

**Wait 60-120 seconds for a PT1H.json file update, then you should see:**
```
==== VNetFlowLogsForwarder Triggered ====
Received 1 Event Grid event(s)
Found 1 Event Grid event(s) in message
Event Type: Microsoft.Storage.BlobCreated
Blob URL: .../PT1H.json
✓ VALIDATED: This is a VNet Flow Log file (PT1H.json)
Got response:202
Logs payload successfully sent to New Relic.
```

✅ **Checkpoint:** Function is processing events and sending to New Relic

---

### Step 5: Verify in New Relic (1 minute)

Log in to New Relic and run:

```sql
SELECT * FROM Log
WHERE logtype = 'azure.vnet.flowlog.validation'
SINCE 15 minutes ago
ORDER BY timestamp DESC
```

**Expected:** You should see validation logs with blob URLs and event details

✅ **Success!** End-to-end flow is working

---

## 📋 Complete One-Liner Sequence

If you want to run everything in sequence (after reviewing the what-if):

```bash
cd /Users/bpavan/repos/logint/nr/newrelic-azure-functions/vnet-flow-logs-spike

# 1. Deploy infrastructure
./deploy.sh bpavan-vnet-logs-arm canadacentral

# Note the PRINCIPAL_ID and FUNCTION_APP_NAME from output, then:

# 2. Grant permissions (replace PRINCIPAL_ID with actual value)
az role assignment create \
  --assignee PRINCIPAL_ID \
  --role "Storage Blob Data Reader" \
  --scope $(az storage account show --name bpavanvnetlogstorage --resource-group bpavan-vnet-logs --query id -o tsv)

# 3. Deploy code
cd ..
npm run package:logforwarder
az functionapp deployment source config-zip \
  --resource-group bpavan-vnet-logs-arm \
  --name FUNCTION_APP_NAME \
  --src LogForwarder.zip
az functionapp restart --resource-group bpavan-vnet-logs-arm --name FUNCTION_APP_NAME

# 4. Monitor
az webapp log tail --resource-group bpavan-vnet-logs-arm --name FUNCTION_APP_NAME
```

---

## ⏱️ Total Time Estimate

| Step | Time |
|------|------|
| 1. Deploy Infrastructure | 5-10 min |
| 2. Grant Permissions | 1 min |
| 3. Deploy Code | 2-3 min |
| 4. Verify Deployment | 2-3 min |
| 5. Check New Relic | 1 min |
| **Total** | **11-18 minutes** |

---

## 🔄 Comparison: Manual vs ARM Template

| Aspect | Manual Setup | ARM Template |
|--------|--------------|--------------|
| Infrastructure Setup | 1-2 hours (clicking through Portal) | 5-10 minutes (automated) |
| Code Deployment | Portal upload | Same (Portal or CLI) |
| Repeatability | Manual each time | One command |
| Errors | Prone to mistakes | Validated automatically |
| Documentation | Custom notes | Self-documenting template |

---

## 🗑️ Cleanup

To delete everything:

```bash
az group delete --name bpavan-vnet-logs-arm --yes --no-wait
```

This will NOT affect your source storage (bpavanvnetlogstorage) as it's in a different resource group.

---

## 📚 More Information

- **Detailed deployment guide:** [ARM_DEPLOYMENT_GUIDE.md](./ARM_DEPLOYMENT_GUIDE.md)
- **Code deployment details:** [DEPLOY_CODE.md](./DEPLOY_CODE.md)
- **Template documentation:** [README-vnetflowlogsforwarder.md](./README-vnetflowlogsforwarder.md)
- **Manual setup comparison:** [MANUAL_UI_SETUP_GUIDE.md](./MANUAL_UI_SETUP_GUIDE.md)

---

**Ready to deploy?** Start with Step 1! 🚀