# ARM Template Spike Validation Guide

## Purpose
This guide helps you validate the VNet Flow Logs ARM template spike without implementing the full function code.

---

## Validation Levels

### Level 1: Static Validation (5 minutes)

**Goal**: Verify ARM template syntax and structure

```bash
# 1. Navigate to repo
cd /Users/bpavan/repos/logint/nr/newrelic-azure-functions

# 2. Validate template syntax
az deployment group validate \
  --resource-group your-test-rg \
  --template-file armTemplates/azuredeploy-vnetflowlogsforwarder.json \
  --parameters newRelicLicenseKey="test-key-for-validation" \
               sourceStorageAccountName="existingstorage" \
               sourceStorageAccountResourceGroup="source-rg"

# Expected output: "provisioningState": "Succeeded"
```

**Validation Checklist**:
- ✅ JSON syntax is valid
- ✅ All resource dependencies are correct
- ✅ Required parameters are present
- ✅ Variable references are valid

---

### Level 2: What-If Analysis (10 minutes)

**Goal**: Preview resources that would be created

```bash
# Run what-if to see planned changes
az deployment group what-if \
  --resource-group your-test-rg \
  --template-file armTemplates/azuredeploy-vnetflowlogsforwarder.json \
  --parameters newRelicLicenseKey="test-key" \
               sourceStorageAccountName="existingstorage" \
               sourceStorageAccountResourceGroup="source-rg"
```

**Expected Resources** (Standard mode):
```
+ Microsoft.EventHub/namespaces
+ Microsoft.EventHub/namespaces/eventhubs
+ Microsoft.EventHub/namespaces/eventhubs/consumergroups
+ Microsoft.EventHub/namespaces/AuthorizationRules (x2)
+ Microsoft.EventGrid/systemTopics
+ Microsoft.EventGrid/systemTopics/eventSubscriptions
+ Microsoft.Storage/storageAccounts (internal)
+ Microsoft.Web/serverfarms
+ Microsoft.Web/sites (Function App)
+ Microsoft.Web/sites/extensions (ZipDeploy)
```

**Expected Resources** (Private VNet mode):
All of the above, plus:
```
+ Microsoft.Network/virtualNetworks
+ Microsoft.Network/privateDnsZones (x4)
+ Microsoft.Network/privateDnsZones/virtualNetworkLinks (x4)
+ Microsoft.Network/privateEndpoints (x4)
+ Microsoft.Network/privateEndpoints/privateDnsZoneGroups (x4)
+ Microsoft.Web/sites/networkConfig
```

---

### Level 3: Test Deployment (1-2 hours)

**Goal**: Deploy to a test environment and verify resources are created correctly

#### Prerequisites

1. **Create a test storage account with dummy VNet Flow Logs structure**:

```bash
# Variables
TEST_RG="spike-validation-rg"
LOCATION="eastus"
SOURCE_STORAGE="vnetflowlogssource$(date +%s)"
TEST_STORAGE="vnetflowlogstest$(date +%s)"

# Create resource group
az group create --name $TEST_RG --location $LOCATION

# Create source storage account (simulates Network Watcher storage)
az storage account create \
  --name $SOURCE_STORAGE \
  --resource-group $TEST_RG \
  --location $LOCATION \
  --sku Standard_LRS

# Create dummy VNet Flow Logs directory structure
az storage container create \
  --name insights-logs-flowlogflowevent \
  --account-name $SOURCE_STORAGE

# Create a test PT1H.json file
echo '{"records":[{"time":"2026-04-23T10:00:00.000Z","macAddress":"00-0D-3A-92-6A-7C","flows":[]}]}' > /tmp/PT1H.json

az storage blob upload \
  --account-name $SOURCE_STORAGE \
  --container-name insights-logs-flowlogflowevent \
  --name "resourceId=/SUBSCRIPTIONS/test/RESOURCEGROUPS/test/PROVIDERS/MICROSOFT.NETWORK/NETWORKSECURITYGROUPS/test-nsg/y=2026/m=04/d=23/h=10/m=00/macAddress=00-0D-3A-92-6A-7C/PT1H.json" \
  --file /tmp/PT1H.json
```

#### Deploy the ARM Template

```bash
# Deploy with standard mode
az deployment group create \
  --resource-group $TEST_RG \
  --template-file armTemplates/azuredeploy-vnetflowlogsforwarder.json \
  --parameters newRelicLicenseKey="YOUR_ACTUAL_NR_LICENSE_KEY" \
               sourceStorageAccountName=$SOURCE_STORAGE \
               sourceStorageAccountResourceGroup=$TEST_RG \
               location=$LOCATION
```

**Deployment Time**: 5-10 minutes

#### Validate Deployed Resources

```bash
# 1. Check Event Grid System Topic
az eventgrid system-topic list --resource-group $TEST_RG --output table

# 2. Check Event Grid Subscription
TOPIC_NAME=$(az eventgrid system-topic list --resource-group $TEST_RG --query "[0].name" -o tsv)
az eventgrid system-topic event-subscription list \
  --resource-group $TEST_RG \
  --system-topic-name $TOPIC_NAME \
  --output table

# 3. Verify filter configuration
az eventgrid system-topic event-subscription show \
  --resource-group $TEST_RG \
  --system-topic-name $TOPIC_NAME \
  --name $(az eventgrid system-topic event-subscription list --resource-group $TEST_RG --system-topic-name $TOPIC_NAME --query "[0].name" -o tsv) \
  --query "filter"

# Expected filter output:
# {
#   "advancedFilters": [
#     { "operatorType": "StringEndsWith", "key": "subject", "values": ["PT1H.json"] },
#     { "operatorType": "StringContains", "key": "subject", "values": ["insights-logs-flowlogflowevent"] }
#   ],
#   "includedEventTypes": ["Microsoft.Storage.BlobCreated"]
# }

# 4. Check Event Hub
az eventhubs namespace list --resource-group $TEST_RG --output table
EVENTHUB_NS=$(az eventhubs namespace list --resource-group $TEST_RG --query "[0].name" -o tsv)
az eventhubs eventhub list --resource-group $TEST_RG --namespace-name $EVENTHUB_NS --output table

# 5. Check Function App
az functionapp list --resource-group $TEST_RG --output table
FUNCTION_APP=$(az functionapp list --resource-group $TEST_RG --query "[0].name" -o tsv)

# 6. Verify Function App settings
az functionapp config appsettings list \
  --name $FUNCTION_APP \
  --resource-group $TEST_RG \
  --query "[?name=='VNETFLOWLOGS_FORWARDER_ENABLED' || name=='SOURCE_STORAGE_ACCOUNT_NAME' || name=='VNETFLOWLOGS_STATE_TABLE_NAME']" \
  --output table

# Expected:
# VNETFLOWLOGS_FORWARDER_ENABLED = true
# SOURCE_STORAGE_ACCOUNT_NAME = {sourceStorageName}
# VNETFLOWLOGS_STATE_TABLE_NAME = vnetflowlogsstate

# 7. Check Function App Managed Identity
az functionapp identity show \
  --name $FUNCTION_APP \
  --resource-group $TEST_RG

# Should show: "type": "SystemAssigned" with a principalId

# 8. Check Internal Storage Account (for Table Storage)
az storage account list --resource-group $TEST_RG --query "[?starts_with(name, 'nrlogs')]" --output table

# 9. Verify Table Storage service exists
INTERNAL_STORAGE=$(az storage account list --resource-group $TEST_RG --query "[?starts_with(name, 'nrlogs')].name" -o tsv)
az storage account show --name $INTERNAL_STORAGE --resource-group $TEST_RG --query "enableTableService"
```

---

### Level 4: Integration Testing (2-3 hours)

**Goal**: Test the end-to-end flow with mock function code

#### Grant Managed Identity Permissions

```bash
# Get Function App's Managed Identity
PRINCIPAL_ID=$(az functionapp identity show \
  --name $FUNCTION_APP \
  --resource-group $TEST_RG \
  --query principalId \
  --output tsv)

# Get Source Storage Account ID
SOURCE_STORAGE_ID=$(az storage account show \
  --name $SOURCE_STORAGE \
  --resource-group $TEST_RG \
  --query id \
  --output tsv)

# Grant Storage Blob Data Reader role
az role assignment create \
  --assignee $PRINCIPAL_ID \
  --role "Storage Blob Data Reader" \
  --scope $SOURCE_STORAGE_ID

echo "Waiting 60 seconds for RBAC propagation..."
sleep 60
```

#### Test Event Grid Event Flow

```bash
# Upload a new blob to trigger Event Grid
echo '{"records":[{"time":"'$(date -u +%Y-%m-%dT%H:%M:%S.000Z)'","macAddress":"00-0D-3A-92-6A-7C","flows":[]}]}' > /tmp/PT1H-test.json

az storage blob upload \
  --account-name $SOURCE_STORAGE \
  --container-name insights-logs-flowlogflowevent \
  --name "resourceId=/SUBSCRIPTIONS/test/RESOURCEGROUPS/test/PROVIDERS/MICROSOFT.NETWORK/NETWORKSECURITYGROUPS/test-nsg/y=2026/m=04/d=23/h=10/m=00/macAddress=00-0D-3A-92-6A-7C/PT1H.json" \
  --file /tmp/PT1H-test.json \
  --overwrite

echo "Blob uploaded. Waiting for Event Grid delivery (30 seconds)..."
sleep 30

# Check Event Hub for messages
az monitor metrics list \
  --resource $EVENTHUB_NS \
  --resource-group $TEST_RG \
  --resource-type "Microsoft.EventHub/namespaces" \
  --metric "IncomingMessages" \
  --start-time $(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --interval PT1M

# Check Function App invocations
az monitor metrics list \
  --resource $FUNCTION_APP \
  --resource-group $TEST_RG \
  --resource-type "Microsoft.Web/sites" \
  --metric "FunctionExecutionCount" \
  --start-time $(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --interval PT1M
```

#### Monitor Function Logs

```bash
# Stream Function App logs
az webapp log tail --name $FUNCTION_APP --resource-group $TEST_RG

# Or view logs in Azure Portal:
echo "View logs: https://portal.azure.com/#@/resource/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$TEST_RG/providers/Microsoft.Web/sites/$FUNCTION_APP/logStream"
```

**Expected Behavior** (without function code):
- ✅ Event Grid detects blob upload
- ✅ Event Grid routes event to Event Hub
- ✅ Event Hub receives message (metric shows IncomingMessages > 0)
- ⚠️ Function triggers but has no VNet Flow Logs handler code yet (will show warning in logs)

---

## Validation Checklist

### ARM Template Structure
- [ ] JSON syntax is valid
- [ ] All resource types are correct
- [ ] Dependencies are properly defined
- [ ] Conditional resources work correctly
- [ ] Variables resolve correctly
- [ ] Outputs are defined

### Event Grid Configuration
- [ ] System Topic is created on source storage account
- [ ] Event Subscription filters for `PT1H.json` files
- [ ] Event Subscription filters for `insights-logs-flowlogflowevent` path
- [ ] Event Subscription routes to Event Hub
- [ ] Event Grid uses blob subject as partition key

### Event Hub Configuration
- [ ] Namespace is created (or uses existing)
- [ ] Event Hub is created (or uses existing)
- [ ] Consumer group is created
- [ ] Authorization rules are created (consumer & producer)
- [ ] Partition count is correct (4 for Basic, 32 for Enterprise)

### Function App Configuration
- [ ] Function App is created
- [ ] App Service Plan is correct (Y1, B1, or EP1)
- [ ] System Assigned Managed Identity is enabled
- [ ] Event Hub connection string is configured
- [ ] Environment variables are set correctly:
  - `VNETFLOWLOGS_FORWARDER_ENABLED=true`
  - `SOURCE_STORAGE_ACCOUNT_NAME`
  - `VNETFLOWLOGS_STATE_TABLE_NAME`
  - `EVENTHUB_NAME`
  - `NR_LICENSE_KEY`
- [ ] Function code is deployed (LogForwarder.zip)

### Storage Account Configuration
- [ ] Internal storage account is created
- [ ] Table Storage service is enabled
- [ ] Public access settings match parameter
- [ ] Connection string is configured for Function App

### Private VNet Configuration (if enabled)
- [ ] Virtual Network is created
- [ ] Function subnet is created with delegation
- [ ] Private endpoints subnet is created
- [ ] Private DNS zones are created (blob, file, queue, table)
- [ ] Virtual network links are created
- [ ] Private endpoints are created for all services
- [ ] Private DNS zone groups are configured
- [ ] Function App VNet integration is configured

### Security Configuration
- [ ] HTTPS only is enforced
- [ ] FTPS is disabled
- [ ] Managed Identity is created
- [ ] No connection strings in source code
- [ ] License key is stored as app setting

---

## Cleanup

```bash
# Delete test resource group (removes all resources)
az group delete --name $TEST_RG --yes --no-wait
```

---

## Success Criteria

The spike is validated if:

✅ **Level 1**: Template passes syntax validation
✅ **Level 2**: What-if analysis shows correct resources
✅ **Level 3**: All resources deploy successfully
✅ **Level 4**: Event Grid events flow to Event Hub

⚠️ **Note**: Function won't forward logs yet (function code not implemented)

---

## Next Spike: Function Code Implementation

After validating the ARM template, the next spike should focus on:

1. **State Management** (1 day)
   - Table Storage cursor read/write
   - First-time processing logic
   - State loss recovery

2. **Delta Extraction** (1 day)
   - Block list API integration
   - Block range download
   - Blob rollover handling

3. **VNet Flow Logs Parsing** (1 day)
   - JSON structure parsing
   - Metadata extraction
   - New Relic format mapping

4. **Integration Testing** (1 day)
   - End-to-end with real Network Watcher
   - Performance testing
   - Zero duplication validation

**Total**: 4-5 days for function code spike

---

## Questions?

If validation fails at any level, check:
1. Azure subscription permissions
2. Source storage account exists
3. Resource group exists
4. Azure region supports all resource types
5. Quota limits (Event Hub, Function App, etc.)