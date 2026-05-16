# VNet Flow Logs Forwarder - ARM Template Deployment Guide

This guide walks you through deploying the VNet Flow Logs forwarder using the ARM template to replicate your successful manual setup.

## 📋 Prerequisites

Before starting, ensure you have:

✅ **Azure CLI** or **Azure PowerShell** installed
✅ **Logged in to Azure** (`az login` or `Connect-AzAccount`)
✅ **Source storage account** with VNet Flow Logs (bpavanvnetlogstorage)
✅ **New Relic License Key** (already in parameters file)
✅ **Appropriate permissions** to create resources and assign roles

## 📁 Files Overview

| File | Purpose |
|------|---------|
| `azuredeploy-vnetflowlogsforwarder.json` | ARM template (infrastructure definition) |
| `azuredeploy-vnetflowlogsforwarder.parameters.json` | Parameters file (configuration values) |
| `deploy.sh` | Automated deployment script (Bash/Azure CLI) |
| `deploy.ps1` | Automated deployment script (PowerShell) |
| `ARM_DEPLOYMENT_GUIDE.md` | This file |

## 🚀 Deployment Options

Choose one of the following methods:

### Option 1: Automated Deployment (Recommended)

#### Using Bash/Azure CLI (Mac/Linux/WSL):

```bash
# Make script executable
chmod +x vnet-flow-logs-spike/deploy.sh

# Run deployment
cd vnet-flow-logs-spike
./deploy.sh bpavan-vnet-logs-arm canadacentral
```

#### Using PowerShell (Windows/Mac/Linux):

```powershell
# Run deployment
cd vnet-flow-logs-spike
.\deploy.ps1 -ResourceGroupName bpavan-vnet-logs-arm -Location canadacentral
```

**What the automated scripts do:**
1. ✅ Validate you're logged in to Azure
2. ✅ Create resource group (if it doesn't exist)
3. ✅ Validate ARM template syntax
4. ✅ Run "what-if" analysis (shows what will be created)
5. ✅ Deploy the template
6. ✅ Extract deployment outputs (Function App name, etc.)
7. ✅ Show you the exact command to grant storage permissions

---

### Option 2: Manual Deployment

#### Step 1: Review Parameters

Edit `azuredeploy-vnetflowlogsforwarder.parameters.json` if needed:

```json
{
  "newRelicLicenseKey": {
    "value": "d377ad18ef50788f2341ed78fa6c853765a1NRAL"  // Already set
  },
  "sourceStorageAccountName": {
    "value": "bpavanvnetlogstorage"  // Your source storage
  },
  "sourceStorageAccountResourceGroup": {
    "value": "bpavan-vnet-logs"  // Source storage RG
  },
  "location": {
    "value": "canadacentral"  // Same region as your manual setup
  }
}
```

#### Step 2: Create Resource Group

```bash
# Azure CLI
az group create --name bpavan-vnet-logs-arm --location canadacentral
```

```powershell
# PowerShell
New-AzResourceGroup -Name bpavan-vnet-logs-arm -Location canadacentral
```

#### Step 3: Validate Template (Optional but Recommended)

```bash
# Azure CLI
az deployment group validate \
  --resource-group bpavan-vnet-logs-arm \
  --template-file azuredeploy-vnetflowlogsforwarder.json \
  --parameters @azuredeploy-vnetflowlogsforwarder.parameters.json
```

```powershell
# PowerShell
Test-AzResourceGroupDeployment `
  -ResourceGroupName bpavan-vnet-logs-arm `
  -TemplateFile azuredeploy-vnetflowlogsforwarder.json `
  -TemplateParameterFile azuredeploy-vnetflowlogsforwarder.parameters.json
```

#### Step 4: Run What-If Analysis (See What Will Be Created)

```bash
# Azure CLI
az deployment group what-if \
  --resource-group bpavan-vnet-logs-arm \
  --template-file azuredeploy-vnetflowlogsforwarder.json \
  --parameters @azuredeploy-vnetflowlogsforwarder.parameters.json
```

```powershell
# PowerShell
Get-AzResourceGroupDeploymentWhatIfResult `
  -ResourceGroupName bpavan-vnet-logs-arm `
  -TemplateFile azuredeploy-vnetflowlogsforwarder.json `
  -TemplateParameterFile azuredeploy-vnetflowlogsforwarder.parameters.json
```

**Expected Resources to be Created:**
- ✅ Event Hub Namespace: `nrlogs-vnetflowlogs-ns-{suffix}`
- ✅ Event Hub: `nrlogs-vnetflowlogs-eventhub`
- ✅ Event Hub Consumer Group: `nrlogs-vnetflowlogs-consumergroup`
- ✅ Event Grid System Topic: `nrlogs-vnetflowlogs-egtopic-{suffix}`
- ✅ Event Grid Subscription: `nrlogs-vnetflowlogs-egsub-{suffix}` (filters PT1H.json)
- ✅ Storage Account (internal): `nrlogs{suffix}`
- ✅ App Service Plan: `nrlogs-serviceplan-{suffix}` (Dynamic Y1)
- ✅ Function App: `nrlogs-vnetflowlogsforwarder-{suffix}`

#### Step 5: Deploy Template

```bash
# Azure CLI
az deployment group create \
  --name vnetflowlogs-$(date +%Y%m%d-%H%M%S) \
  --resource-group bpavan-vnet-logs-arm \
  --template-file azuredeploy-vnetflowlogsforwarder.json \
  --parameters @azuredeploy-vnetflowlogsforwarder.parameters.json
```

```powershell
# PowerShell
New-AzResourceGroupDeployment `
  -Name "vnetflowlogs-$(Get-Date -Format 'yyyyMMdd-HHmmss')" `
  -ResourceGroupName bpavan-vnet-logs-arm `
  -TemplateFile azuredeploy-vnetflowlogsforwarder.json `
  -TemplateParameterFile azuredeploy-vnetflowlogsforwarder.parameters.json
```

⏱️ **Deployment time: 5-10 minutes**

#### Step 6: Get Deployment Outputs

```bash
# Azure CLI - Get Function App name
az deployment group show \
  --resource-group bpavan-vnet-logs-arm \
  --name <deployment-name> \
  --query properties.outputs.functionAppName.value \
  --output tsv
```

```powershell
# PowerShell - Get deployment outputs
$deployment = Get-AzResourceGroupDeployment -ResourceGroupName bpavan-vnet-logs-arm -Name <deployment-name>
$deployment.Outputs.functionAppName.Value
$deployment.Outputs.eventHubName.Value
$deployment.Outputs.storageAccountName.Value
```

---

## 🔐 Post-Deployment: Grant Storage Permissions

**⚠️ CRITICAL STEP - Function won't work without this!**

The Function App needs read access to your source storage account (bpavanvnetlogstorage).

### Step 1: Get Function App's Managed Identity

```bash
# Azure CLI
FUNCTION_APP_NAME="<function-app-name-from-deployment>"
PRINCIPAL_ID=$(az functionapp identity show \
  --name $FUNCTION_APP_NAME \
  --resource-group bpavan-vnet-logs-arm \
  --query principalId \
  --output tsv)

echo "Principal ID: $PRINCIPAL_ID"
```

```powershell
# PowerShell
$FunctionAppName = "<function-app-name-from-deployment>"
$webapp = Get-AzWebApp -ResourceGroupName bpavan-vnet-logs-arm -Name $FunctionAppName
$PrincipalId = $webapp.Identity.PrincipalId

Write-Host "Principal ID: $PrincipalId"
```

### Step 2: Grant "Storage Blob Data Reader" Role

```bash
# Azure CLI
SOURCE_STORAGE_ACCOUNT=$(az storage account show \
  --name bpavanvnetlogstorage \
  --resource-group bpavan-vnet-logs \
  --query id \
  --output tsv)

az role assignment create \
  --assignee $PRINCIPAL_ID \
  --role "Storage Blob Data Reader" \
  --scope $SOURCE_STORAGE_ACCOUNT

echo "✅ Storage permissions granted!"
```

```powershell
# PowerShell
$sourceStorage = Get-AzStorageAccount `
  -ResourceGroupName bpavan-vnet-logs `
  -Name bpavanvnetlogstorage

New-AzRoleAssignment `
  -ObjectId $PrincipalId `
  -RoleDefinitionName "Storage Blob Data Reader" `
  -Scope $sourceStorage.Id

Write-Host "✅ Storage permissions granted!"
```

---

## ✅ Validation & Testing

### 1. Check Function App Status

```bash
# Azure CLI
az functionapp list --resource-group bpavan-vnet-logs-arm --output table
```

```powershell
# PowerShell
Get-AzWebApp -ResourceGroupName bpavan-vnet-logs-arm | Format-Table Name, State, Location
```

### 2. Verify Event Grid Subscription

```bash
# Azure CLI
az eventgrid system-topic event-subscription list \
  --resource-group bpavan-vnet-logs-arm \
  --system-topic-name nrlogs-vnetflowlogs-egtopic-* \
  --output table
```

Check that the subscription filters for:
- ✅ Event Type: `Microsoft.Storage.BlobCreated`
- ✅ Subject Ends With: `PT1H.json`
- ✅ Subject Contains: `insights-logs-flowlogflowevent`

### 3. Check Event Hub Metrics

```bash
# Azure CLI - Check incoming messages
az monitor metrics list \
  --resource <event-hub-namespace-resource-id> \
  --metric IncomingMessages \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --interval PT5M
```

### 4. Monitor Function Logs

```bash
# Azure CLI - Live log streaming
az webapp log tail \
  --name <function-app-name> \
  --resource-group bpavan-vnet-logs-arm
```

**Expected logs:**
```
==== VNetFlowLogsForwarder Triggered ====
Received 1 Event Grid event(s)
Event Type: Microsoft.Storage.BlobCreated
Blob URL: .../PT1H.json
✓ VALIDATED: This is a VNet Flow Log file (PT1H.json)
Got response:202
Logs payload successfully sent to New Relic.
```

### 5. Check New Relic Logs

Log in to New Relic and run this query:

```sql
SELECT * FROM Log
WHERE logtype = 'azure.vnet.flowlog.validation'
SINCE 15 minutes ago
ORDER BY timestamp DESC
```

---

## 🔍 Troubleshooting

### Issue: Function not triggering

**Check:**
1. Event Grid subscription is active
2. Event Hub is receiving messages
3. Function App is running

```bash
# Check Function App status
az functionapp show \
  --name <function-app-name> \
  --resource-group bpavan-vnet-logs-arm \
  --query state
```

### Issue: "Unauthorized" or "403" errors in function logs

**Fix:** The Managed Identity doesn't have read permissions on the source storage account. Re-run the role assignment command above.

### Issue: No logs in New Relic

**Check:**
1. New Relic License Key is correct
2. Function logs show HTTP 202 responses
3. Function has internet connectivity

```bash
# Verify environment variables
az functionapp config appsettings list \
  --name <function-app-name> \
  --resource-group bpavan-vnet-logs-arm \
  --query "[?name=='NR_LICENSE_KEY']"
```

### Issue: Deployment fails

**Common causes:**
1. **Resource name conflict**: Delete resources and try again
2. **Quota exceeded**: Check your subscription quotas
3. **Invalid parameters**: Review parameters file

```bash
# Get deployment error details
az deployment group show \
  --resource-group bpavan-vnet-logs-arm \
  --name <deployment-name> \
  --query properties.error
```

---

## 🗑️ Cleanup

To delete all resources created by the ARM template:

```bash
# Azure CLI
az group delete --name bpavan-vnet-logs-arm --yes --no-wait
```

```powershell
# PowerShell
Remove-AzResourceGroup -Name bpavan-vnet-logs-arm -Force
```

⚠️ **Note:** This will delete everything in the resource group. Your source storage account (bpavanvnetlogstorage) will NOT be affected as it's in a different resource group.

---

## 📊 Comparison: Manual Setup vs ARM Template

| Aspect | Manual Setup | ARM Template |
|--------|--------------|--------------|
| **Time** | 1-2 hours | 5-10 minutes |
| **Repeatability** | Manual each time | Fully automated |
| **Errors** | Prone to mistakes | Consistent |
| **Documentation** | Your notes | Self-documenting |
| **Naming** | Custom names | Auto-generated with suffix |
| **Validation** | Manual testing | Built-in what-if analysis |

---

## 🎯 Next Steps

After successful deployment:

1. ✅ Verify logs are flowing to New Relic
2. ✅ Create dashboards in New Relic for network monitoring
3. ✅ Set up alerts for suspicious network activity
4. 📦 Consider deploying to production with the same template
5. 📝 Update parameters file for different environments (dev/staging/prod)

---

## 🤝 Support

If you encounter issues:

1. Check the **Troubleshooting** section above
2. Review Azure Activity Logs in the Portal
3. Check function app logs for detailed error messages
4. Refer to the [ARM Template Documentation](./README-vnetflowlogsforwarder.md)

---

## 📚 Additional Resources

- [ARM Template Reference](./README-vnetflowlogsforwarder.md)
- [Manual Setup Guide](./MANUAL_UI_SETUP_GUIDE.md) (for comparison)
- [Spike Summary](./SPIKE_SUMMARY_VNetFlowLogs.md) (architectural decisions)
- [Azure ARM Template Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/templates/)

---

**Deployment Guide Version:** 1.0
**Last Updated:** April 24, 2026
**Status:** Ready for deployment