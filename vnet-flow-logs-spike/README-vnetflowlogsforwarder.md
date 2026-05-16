# Azure VNet Flow Logs Forwarder - ARM Template Documentation

## Overview

This ARM template deploys a stateful, event-driven Azure Function that ingests Azure Virtual Network (VNet) Flow Logs from Azure Blob Storage and forwards them to New Relic Logs. The solution uses Event Grid to detect when Network Watcher appends new flow log data to hourly blob files, routes these events through an Event Hub, and processes them with a custom Azure Function that tracks state using Azure Table Storage to avoid data duplication.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    CUSTOMER-OWNED (Prerequisites)                       │
│                                                                         │
│   Azure VNet ──→ Network Watcher ──→ Blob Storage (PT1H.json files)    │
│                                            │                            │
└────────────────────────────────────────────┼────────────────────────────┘
                                             │
          ┌──────────────────────────────────┼──────────────────────────┐
          │  PROVISIONED BY THIS ARM TEMPLATE                           │
          │                              │                              │
          │                              ▼                              │
          │                    ┌─────────────────┐                      │
          │                    │  Event Grid      │                      │
          │                    │  System Topic    │                      │
          │                    │  (BlobCreated)   │                      │
          │                    └────────┬─────────┘                      │
          │                             │                               │
          │              subject as PartitionKey                        │
          │                             │                               │
          │                             ▼                               │
          │                    ┌─────────────────┐                      │
          │                    │   Event Hub      │                      │
          │                    │  (ordered queue) │                      │
          │                    └────────┬─────────┘                      │
          │                             │                               │
          │                  batch of 5-20 events                       │
          │                             │                               │
          │                             ▼                               │
          │  ┌─────────────┐   ┌─────────────────┐                      │
          │  │ Table        │◄──│  Azure Function  │                      │
          │  │ Storage      │──►│  (VNet Flow Logs │                      │
          │  │ (cursors)    │   │   Forwarder)     │                      │
          │  └─────────────┘   └────────┬─────────┘                      │
          │                             │                               │
          └─────────────────────────────┼───────────────────────────────┘
                                        │
                              Parse + Compress + Send
                                        │
                                        ▼
                               ┌─────────────────┐
                               │  New Relic       │
                               │  Log API         │
                               │  (log-api.newrelic│
                               │   .com/log/v1)   │
                               └─────────────────┘
```

## Key Features

### 1. **Event-Driven Architecture**
- **Event Grid System Topic**: Monitors the customer's storage account for blob creation events
- **Advanced Filtering**: Only processes `PT1H.json` files in the `insights-logs-flowlogflowevent` container path
- **Event Hub Integration**: Routes events through Event Hub with partition keys based on blob file paths to ensure chronological ordering

### 2. **Stateful Processing (Zero Duplication)**
- **Azure Table Storage**: Maintains cursor/bookmark state for each blob file
- **Block-Level Tracking**: Tracks the exact number of blocks processed per file
- **Delta Extraction**: Downloads only newly appended blocks (not the entire file)
- **Eliminates 60x Duplication**: Unlike stateless forwarders, this processes each minute's new data exactly once

### 3. **Throttled Batch Processing**
- **Configurable Batch Size**: Default 5-20 events per batch (lower than standard to prevent timeouts)
- **Prevents Overload**: Controls memory and execution time during high network traffic
- **Ordered Processing**: Event Hub partition keys ensure files are processed in order

### 4. **Private VNet Support**
- **Optional Isolation**: Can disable public access to internal storage account
- **Private Endpoints**: Creates private endpoints for blob, file, queue, and table storage services
- **Private DNS Zones**: Automatic DNS resolution for private endpoints
- **VNet Integration**: Function app integrated into dedicated subnet

## Resources Created

| Resource Type | Resource Name Pattern | Purpose |
|---------------|----------------------|---------|
| **Event Hub Namespace** | `nrlogs-vnetflowlogs-ns-{suffix}` | Messaging infrastructure for Event Grid events |
| **Event Hub** | `nrlogs-vnetflowlogs-eventhub` | Queue for blob creation events |
| **Event Hub Consumer Group** | `nrlogs-vnetflowlogs-consumergroup` | Dedicated consumer for the Function App |
| **Event Grid System Topic** | `nrlogs-vnetflowlogs-egtopic-{suffix}` | Captures events from source storage account |
| **Event Grid Subscription** | `nrlogs-vnetflowlogs-egsub-{suffix}` | Filters and routes blob creation events to Event Hub |
| **Storage Account (Internal)** | `nrlogs{suffix}` | Function state storage (includes Table Storage for cursors) |
| **App Service Plan** | `nrlogs-serviceplan-{suffix}` | Hosting plan for Function App (Dynamic Y1 or Basic B1 for VNet) |
| **Function App** | `nrlogs-vnetflowlogsforwarder-{suffix}` | Processes events and forwards logs to New Relic |
| **Virtual Network** | `nrlogs{suffix}-virtual-network` | (Optional) Private network for Function App |
| **Private Endpoints** | `nrlogs{suffix}-{service}-private-endpoint` | (Optional) Private endpoints for blob, file, queue, table |
| **Private DNS Zones** | `privatelink.{service}.core.windows.net` | (Optional) DNS zones for private endpoint resolution |

## Parameters

### Required Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `newRelicLicenseKey` | string | New Relic License Key for authentication |
| `sourceStorageAccountName` | string | Name of the storage account where Network Watcher writes VNet Flow Logs (must exist) |
| `sourceStorageAccountResourceGroup` | string | Resource Group name where the source storage account is located |

### Optional Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `eventHubNamespace` | string | (auto-create) | Event Hub Namespace name. Leave blank to create automatically |
| `eventHubName` | string | (auto-create) | Event Hub name. Leave blank to create automatically |
| `location` | string | (resource group location) | Azure region for deployment |
| `newRelicEndpoint` | string | `https://log-api.newrelic.com/log/v1` | New Relic Logs API endpoint (use EU endpoint for EU accounts) |
| `logCustomAttributes` | string | "" | Semicolon-separated custom attributes (e.g., `environment:prod;team:networking`) |
| `maxEventBatchSize` | int | 20 | Maximum events per batch (lower than standard to prevent timeouts) |
| `minEventBatchSize` | int | 5 | Minimum events per batch |
| `maxWaitTime` | string | `00:00:30` | Maximum time to wait before delivering a batch (format: HH:MM:SS) |
| `maxRetriesToResendLogs` | int | 3 | Number of retry attempts on failure |
| `retryInterval` | int | 2000 | Milliseconds to wait between retries |
| `scalingMode` | string | `Basic` | `Basic` (Dynamic Y1) or `Enterprise` (ElasticPremium EP1 with 20 workers) |
| `disablePublicAccessToStorageAccount` | bool | false | Enable private VNet deployment (requires Basic plan or higher) |

## Deployment Instructions

### Prerequisites

1. **Azure VNet with Network Watcher Enabled**
   - VNet Flow Logs configured
   - Flow logs being written to an Azure Storage Account

2. **Source Storage Account**
   - Must exist in the same subscription
   - Must contain VNet Flow Logs in the path pattern:
     ```
     {storageAccount}/insights-logs-flowlogflowevent/
       resourceId=/SUBSCRIPTIONS/{subId}/RESOURCEGROUPS/{rg}/
         PROVIDERS/MICROSOFT.NETWORK/NETWORKSECURITYGROUPS/{nsg}/
           y={year}/m={month}/d={day}/h={hour}/m=00/
             macAddress={mac}/PT1H.json
     ```

3. **New Relic Account**
   - Valid License Key
   - Appropriate API endpoint (US or EU)

### Deployment via Azure Portal

1. Navigate to **Azure Portal** > **Create a resource** > **Template deployment (deploy using custom templates)**
2. Click **Build your own template in the editor**
3. Copy and paste the contents of `azuredeploy-vnetflowlogsforwarder.json`
4. Click **Save**
5. Fill in the required parameters:
   - **New Relic License Key**: Your New Relic license key
   - **Source Storage Account Name**: Storage account containing VNet Flow Logs
   - **Source Storage Account Resource Group**: Resource group of the source storage account
6. Review optional parameters and adjust as needed
7. Click **Review + create** > **Create**

### Deployment via Azure CLI

```bash
# Set variables
RESOURCE_GROUP="my-resource-group"
LOCATION="eastus"
NR_LICENSE_KEY="your-new-relic-license-key"
SOURCE_STORAGE_ACCOUNT="sourceStorageAccountName"
SOURCE_STORAGE_RG="sourceStorageResourceGroup"

# Create resource group (if it doesn't exist)
az group create --name $RESOURCE_GROUP --location $LOCATION

# Deploy the template
az deployment group create \
  --resource-group $RESOURCE_GROUP \
  --template-file azuredeploy-vnetflowlogsforwarder.json \
  --parameters newRelicLicenseKey=$NR_LICENSE_KEY \
               sourceStorageAccountName=$SOURCE_STORAGE_ACCOUNT \
               sourceStorageAccountResourceGroup=$SOURCE_STORAGE_RG
```

### Deployment via PowerShell

```powershell
# Set variables
$resourceGroupName = "my-resource-group"
$location = "eastus"
$nrLicenseKey = "your-new-relic-license-key"
$sourceStorageAccount = "sourceStorageAccountName"
$sourceStorageRG = "sourceStorageResourceGroup"

# Create resource group (if it doesn't exist)
New-AzResourceGroup -Name $resourceGroupName -Location $location

# Deploy the template
New-AzResourceGroupDeployment `
  -ResourceGroupName $resourceGroupName `
  -TemplateFile azuredeploy-vnetflowlogsforwarder.json `
  -newRelicLicenseKey $nrLicenseKey `
  -sourceStorageAccountName $sourceStorageAccount `
  -sourceStorageAccountResourceGroup $sourceStorageRG
```

## Post-Deployment Configuration

### 1. Grant Read Permissions to Source Storage Account

The Function App uses a **System Assigned Managed Identity** to access the source storage account. You must grant the appropriate permissions:

```bash
# Get the Function App's Managed Identity Principal ID
FUNCTION_APP_NAME="nrlogs-vnetflowlogsforwarder-{suffix}"
PRINCIPAL_ID=$(az functionapp identity show \
  --name $FUNCTION_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --query principalId \
  --output tsv)

# Grant "Storage Blob Data Reader" role on the source storage account
SOURCE_STORAGE_ACCOUNT_ID=$(az storage account show \
  --name $SOURCE_STORAGE_ACCOUNT \
  --resource-group $SOURCE_STORAGE_RG \
  --query id \
  --output tsv)

az role assignment create \
  --assignee $PRINCIPAL_ID \
  --role "Storage Blob Data Reader" \
  --scope $SOURCE_STORAGE_ACCOUNT_ID
```

### 2. Verify Event Grid Subscription

Check that the Event Grid subscription is properly filtering events:

```bash
az eventgrid system-topic event-subscription show \
  --name nrlogs-vnetflowlogs-egsub-{suffix} \
  --resource-group $RESOURCE_GROUP \
  --system-topic-name nrlogs-vnetflowlogs-egtopic-{suffix}
```

Verify the filter includes:
- Event type: `Microsoft.Storage.BlobCreated`
- Subject ends with: `PT1H.json`
- Subject contains: `insights-logs-flowlogflowevent`

### 3. Monitor Function Execution

```bash
# View live logs
az webapp log tail --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP

# Check function invocations
az monitor metrics list \
  --resource $FUNCTION_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --resource-type "Microsoft.Web/sites" \
  --metric FunctionExecutionCount
```

## Environment Variables (Automatic Configuration)

These environment variables are automatically configured by the ARM template:

| Variable | Description |
|----------|-------------|
| `VNETFLOWLOGS_FORWARDER_ENABLED` | Set to `true` to enable VNet Flow Logs processing |
| `VNETFLOWLOGS_STATE_TABLE_NAME` | Azure Table Storage table name for cursor state (default: `vnetflowlogsstate`) |
| `SOURCE_STORAGE_ACCOUNT_NAME` | Source storage account name containing flow logs |
| `EVENTHUB_NAME` | Event Hub name for receiving Event Grid events |
| `EVENTHUB_CONSUMER_CONNECTION` | Event Hub connection string (consumer policy) |
| `EVENTHUB_CONSUMER_GROUP` | Consumer group name |
| `NR_LICENSE_KEY` | New Relic license key |
| `NR_ENDPOINT` | New Relic Logs API endpoint |
| `NR_TAGS` | Custom attributes for log enrichment |
| `NR_MAX_RETRIES` | Maximum retry attempts |
| `NR_RETRY_INTERVAL` | Retry interval in milliseconds |

## Scaling Considerations

### Basic Mode (Default)
- **Plan**: Dynamic (Consumption) Y1
- **Cost**: Pay per execution
- **Scaling**: Automatic (up to 200 instances)
- **Best For**: Most deployments (hundreds of VMs)

### Enterprise Mode
- **Plan**: ElasticPremium EP1
- **Cost**: Fixed monthly cost + execution cost
- **Scaling**: Automatic (up to 20 workers)
- **Event Hub**: 32 partitions (vs 4 in Basic)
- **Throughput**: 40 throughput units with auto-inflate
- **Best For**: Large-scale deployments (thousands of VMs, high traffic volumes)

## Troubleshooting

### No Logs Appearing in New Relic

1. **Check Event Grid Events Are Being Generated**
   ```bash
   az eventgrid system-topic event-subscription show \
     --name nrlogs-vnetflowlogs-egsub-{suffix} \
     --resource-group $RESOURCE_GROUP \
     --system-topic-name nrlogs-vnetflowlogs-egtopic-{suffix} \
     --include-full-endpoint-url
   ```

2. **Verify Function App Managed Identity Has Permissions**
   ```bash
   az role assignment list \
     --assignee $PRINCIPAL_ID \
     --scope $SOURCE_STORAGE_ACCOUNT_ID
   ```
   Should show "Storage Blob Data Reader" role

3. **Check Function Logs for Errors**
   ```bash
   az webapp log tail --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP
   ```

4. **Verify Event Hub is Receiving Messages**
   ```bash
   az monitor metrics list \
     --resource /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.EventHub/namespaces/{namespace} \
     --metric IncomingMessages
   ```

### Function Timeouts

If you're seeing timeout errors:

1. **Reduce Batch Size**
   - Update `maxEventBatchSize` parameter to a lower value (e.g., 10)

2. **Upgrade to Enterprise Plan**
   - Set `scalingMode` parameter to `Enterprise`
   - Provides more CPU and memory per instance

3. **Check Network Latency**
   - Ensure Function App and source storage are in the same region

### Table Storage State Issues

If you suspect the cursor state is incorrect:

```bash
# View table storage contents (requires Storage Table Data Reader role)
az storage table list \
  --account-name nrlogs{suffix} \
  --query "[?name=='vnetflowlogsstate']"
```

To reset state (will cause reprocessing of current hour's data):
```bash
az storage entity delete \
  --account-name nrlogs{suffix} \
  --table-name vnetflowlogsstate \
  --partition-key {blobFilePath} \
  --row-key {blobFilePath}
```

## Cost Estimation

### Basic Mode (Typical Deployment)

**Assumptions**: 100 VMs, 60 updates/hour per VM = 6,000 function executions/hour

| Resource | Monthly Cost (USD) |
|----------|-------------------|
| Function App (Consumption) | ~$20 (6,000 exec/hr × 730 hrs × $0.20/million) |
| Event Hub (Standard) | ~$20 (1 throughput unit) |
| Storage Account (Internal) | ~$5 (100 GB table storage, minimal transactions) |
| Event Grid | ~$1 (6,000 events/hr × 730 hrs × $0.60/million) |
| **Total** | **~$46/month** |

### Enterprise Mode (Large Deployment)

**Assumptions**: 1,000 VMs, 60 updates/hour per VM = 60,000 function executions/hour

| Resource | Monthly Cost (USD) |
|----------|-------------------|
| Function App (ElasticPremium EP1) | ~$160 (base plan) |
| Event Hub (Standard with auto-inflate) | ~$200 (up to 40 throughput units) |
| Storage Account (Internal) | ~$20 (1 TB table storage) |
| Event Grid | ~$10 (60,000 events/hr × 730 hrs × $0.60/million) |
| **Total** | **~$390/month** |

## Limitations

1. **Source Storage Account**: Must be in the same subscription as the deployment
2. **Event Grid Filtering**: Only processes `PT1H.json` files in the standard Network Watcher path
3. **Table Storage State**: If state is lost, the current hour's data will be reprocessed (but subsequent hours will be correct)
4. **Event Hub Retention**: 1 day retention (unprocessed events older than 24 hours are lost)

## Security Considerations

1. **Managed Identity**: Function App uses System Assigned Managed Identity for source storage access (no keys stored)
2. **HTTPS Only**: All communication enforced over HTTPS
3. **FTPS Disabled**: FTP access to Function App is disabled
4. **Network Isolation**: Optional private VNet deployment for compliance requirements
5. **License Key**: Stored as app setting (consider using Azure Key Vault for enhanced security)

## Next Steps

After successful deployment:

1. ✅ Grant read permissions to source storage account
2. ✅ Verify Event Grid events are flowing
3. ✅ Check New Relic Logs for incoming VNet Flow Logs
4. 📊 Create dashboards and alerts in New Relic
5. 🔍 Set up custom queries for network security analysis

## Support

For issues related to:
- **ARM Template**: Open an issue on the [GitHub repository](https://github.com/newrelic/newrelic-azure-functions)
- **Azure Resources**: Consult Azure documentation or Azure Support
- **New Relic**: Contact New Relic Support or visit [New Relic Community](https://discuss.newrelic.com/)