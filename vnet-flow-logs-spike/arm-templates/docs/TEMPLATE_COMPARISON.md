# ARM Template Comparison: VNet Flow Logs vs Existing Templates

## Overview

This document compares the **new VNet Flow Logs ARM templates** with the **existing BlobForwarder and EventHubForwarder templates** in the repository.

---

## Template Inventory

### Existing Templates (`/armTemplates/`)

| Template | Purpose | Lines | Complexity |
|----------|---------|-------|------------|
| **azuredeploy-blobforwarder.json** | Forward logs from existing storage account blobs to New Relic | 558 | Medium |
| **azuredeploy-eventhubforwarder.json** | Forward logs from Event Hub to New Relic (with optional Activity Logs integration) | 875 | High |

### New VNet Flow Logs Templates (`/vnet-flow-logs-spike/arm-templates/`)

| Template | Purpose | Lines | Complexity |
|----------|---------|-------|------------|
| **azuredeploy-vnetflowlogs-complete.json** | Complete VNet Flow Logs pipeline from scratch (VNet + Flow Logs + Forwarder) | 562 | Medium |
| **azuredeploy-vnetflowlogsforwarder.json** | Forwarder only (assumes Flow Logs already exist) | 839 | High |

---

## Key Differences

### 1. **Use Case & Scope**

| Feature | BlobForwarder | EventHubForwarder | VNet Flow Logs (New) |
|---------|---------------|-------------------|----------------------|
| **Primary Use Case** | Forward logs from existing blobs | Forward platform logs via Event Hub | Forward VNet Flow Logs specifically |
| **Creates Infrastructure** | No (uses existing storage) | Optionally creates Event Hub | Yes (creates VNet, NSG, Flow Logs) |
| **Target Log Type** | Any blob-based logs | Activity Logs, Diagnostic Logs | VNet Flow Logs (PT1H.json) |
| **Event Source** | Event Grid on existing storage | Event Hub (direct) | Event Grid on new storage |

### 2. **Architecture Pattern**

#### BlobForwarder Architecture
```
[Existing Storage Account]
         ↓ (Event Grid)
  [Function App (Blob Trigger)]
         ↓
   [New Relic]
```

**Key Characteristics:**
- Uses **existing** storage account
- Direct Event Grid → Function trigger
- No Event Hub involved
- Simple, minimal infrastructure

#### EventHubForwarder Architecture
```
[Azure Diagnostic Settings]
         ↓
   [Event Hub]
         ↓ (Event Hub Trigger)
    [Function App]
         ↓
   [New Relic]
```

**Key Characteristics:**
- Uses **existing or creates** Event Hub
- Direct Event Hub → Function trigger
- Can enable Activity Logs automatically
- Optional Premium/Enterprise scaling
- More complex with Activity Log integration

#### VNet Flow Logs Architecture (New)
```
[VNet + NSG]
      ↓
[Network Watcher VNet Flow Logs]
      ↓
[Source Storage Account (PT1H.json)]
      ↓ (Event Grid)
  [Event Hub]
      ↓ (Event Hub Trigger)
  [Function App]
      ↓
 [New Relic]
```

**Key Characteristics:**
- Creates **entire infrastructure** from scratch
- Event Grid → Event Hub → Function (two-hop pattern)
- Specifically designed for VNet Flow Logs
- Filters for PT1H.json files only
- Complete end-to-end solution

### 3. **Infrastructure Created**

| Resource | BlobForwarder | EventHubForwarder | VNet Flow Logs |
|----------|---------------|-------------------|----------------|
| Virtual Network | ❌ | ❌ | ✅ (with subnet, NSG) |
| VNet Flow Logs | ❌ | ❌ | ✅ (targets VNet, not NSG) |
| Source Storage Account | ❌ (uses existing) | ❌ | ✅ (for PT1H.json) |
| Event Grid | ✅ (on existing storage) | ❌ | ✅ (on new storage) |
| Event Hub | ❌ | ✅ (optional) | ✅ (always) |
| Event Hub Consumer Group | ❌ | ✅ | ❌ (uses $Default) |
| Function App | ✅ | ✅ | ✅ |
| Internal Storage | ✅ | ✅ | ✅ |
| Application Insights | ✅ | ✅ | ✅ |
| Activity Log Integration | ❌ | ✅ (optional) | ❌ |
| Private VNet Support | ✅ (optional) | ❌ | ❌ |

### 4. **Naming Conventions**

| Template | Naming Pattern | Example |
|----------|----------------|---------|
| **BlobForwarder** | `nrlogs-blobforwarder-{hash}` | `nrlogs-blobforwarder-abc123xyz` |
| **EventHubForwarder** | `nrlogs-eventhubforwarder-{hash}` | `nrlogs-eventhubforwarder-def456` |
| **VNet Flow Logs** | `bpavan-vnet-{resource}-{hash}` | `bpavan-vnet-func-7lk6nyehuzkgi` |

**Note:** VNet Flow Logs template uses custom `bpavan-` prefix for easy identification of spike resources.

### 5. **Key Parameters**

#### Common Parameters (All Templates)
- `newRelicLicenseKey` - New Relic license key
- `newRelicEndpoint` - NR Logs API endpoint (US/EU)
- `location` - Azure region

#### BlobForwarder Specific
- `targetStorageAccountName` - **Required**: Existing storage account name
- `targetContainerName` - **Required**: Container with logs to forward
- `disablePublicAccessToStorageAccount` - Creates private VNet setup

#### EventHubForwarder Specific
- `eventHubNamespace` - Optional: Existing Event Hub Namespace
- `eventHubName` - Optional: Existing Event Hub name
- `scalingMode` - Basic or Enterprise (Premium Function App)
- `forwardAdministrativeAzureActivityLogs` - Auto-setup Activity Logs
- `forwardServiceHealthAzureActivityLogs` - Include Service Health logs
- Plus 10+ more Activity Log category toggles

#### VNet Flow Logs Specific
- `vnetName` - Name for the VNet to create
- `vnetAddressPrefix` - VNet CIDR (e.g., 10.1.0.0/16)
- `subnetName` - Subnet name
- `subnetAddressPrefix` - Subnet CIDR
- `flowLogsRetentionDays` - Retention in storage (0-365)

### 6. **Event Hub Configuration**

| Feature | BlobForwarder | EventHubForwarder | VNet Flow Logs |
|---------|---------------|-------------------|----------------|
| **Uses Event Hub** | ❌ No | ✅ Yes | ✅ Yes |
| **Event Hub Tier** | N/A | Standard | **Basic** |
| **Consumer Groups** | N/A | Creates custom | Uses **$Default** |
| **Partitions** | N/A | 4 | **1** |
| **Authorization Rules** | N/A | Consumer + Producer | Consumer + Producer |

**Why Basic tier?** VNet Flow Logs template optimized for cost during spike/POC phase. Basic tier doesn't support custom consumer groups, so uses `$Default`.

### 7. **Triggering Mechanism**

| Template | Trigger Type | Trigger Source |
|----------|--------------|----------------|
| **BlobForwarder** | Event Grid (Blob) | Direct from storage account |
| **EventHubForwarder** | Event Hub | Direct from Event Hub |
| **VNet Flow Logs** | Event Hub | Via Event Grid → Event Hub |

**Why two hops?** VNet Flow Logs uses Event Grid to filter for PT1H.json files before sending to Event Hub, ensuring the function only processes relevant flow log files.

### 8. **Idempotency**

| Template | Idempotency Approach |
|----------|---------------------|
| **BlobForwarder** | `uniqueString(resourceGroup().id, parameters('targetStorageAccountName'), parameters('targetContainerName'))` |
| **EventHubForwarder** | `uniqueString(resourceGroup().id)` |
| **VNet Flow Logs** | `uniqueString(resourceGroup().id)` |

All templates use `uniqueString()` to ensure consistent naming within the same resource group = safe to re-run.

### 9. **Private Network Support**

| Template | Private VNet Support | Implementation |
|----------|---------------------|----------------|
| **BlobForwarder** | ✅ Yes (optional) | Creates VNet, subnets, private endpoints, DNS zones |
| **EventHubForwarder** | ❌ No | N/A |
| **VNet Flow Logs** | ❌ No (creates public VNet) | Creates VNet for flow logs source, not for Function App isolation |

**Note:** BlobForwarder's private VNet feature is for securing the Function App communication with storage, not for the log source itself.

### 10. **Activity Logs Integration**

| Template | Activity Logs Support | Categories |
|----------|----------------------|------------|
| **BlobForwarder** | ❌ No | N/A |
| **EventHubForwarder** | ✅ Yes (optional) | Administrative, Service Health, Alert, Autoscale, Policy, Recommendation, Resource Health, Security |
| **VNet Flow Logs** | ❌ No | Only VNet Flow Logs |

**EventHubForwarder** is the only template that can automatically configure Azure Activity Logs forwarding to New Relic.

### 11. **Function App Scaling**

| Template | Scaling Options |
|----------|----------------|
| **BlobForwarder** | Dynamic (Consumption Plan) |
| **EventHubForwarder** | Basic (Dynamic) or **Enterprise (Premium EP1)** |
| **VNet Flow Logs** | Dynamic (Consumption Plan) |

**EventHubForwarder** offers Premium scaling for high-throughput scenarios.

### 12. **Batch Processing Configuration**

| Parameter | BlobForwarder | EventHubForwarder | VNet Flow Logs |
|-----------|---------------|-------------------|----------------|
| **maxEventBatchSize** | N/A | 500 | **20** |
| **minEventBatchSize** | N/A | 20 | **5** |
| **maxWaitTime** | N/A | 00:00:30 | **00:00:30** |

**VNet Flow Logs** uses smaller batches because PT1H.json files arrive less frequently (every ~60 seconds).

### 13. **Special Features**

#### BlobForwarder Unique Features
- ✅ Works with **any existing storage account**
- ✅ Optional **private VNet** setup for security
- ✅ Minimal infrastructure overhead
- ✅ Supports custom blob containers

#### EventHubForwarder Unique Features
- ✅ **Activity Logs** auto-configuration (8+ categories)
- ✅ **Premium (Enterprise) scaling** for high throughput
- ✅ Diagnostic Settings auto-creation
- ✅ Subscription-level log collection
- ✅ Creates Event Hub if needed

#### VNet Flow Logs Unique Features
- ✅ **Complete infrastructure** from scratch
- ✅ Uses new **VNet-level Flow Logs** (not deprecated NSG flow logs)
- ✅ **PT1H.json filtering** via Event Grid
- ✅ Optimized for **spike/POC** scenarios
- ✅ **Network Watcher** integration
- ✅ **NSG + VNet** creation included
- ✅ Cost-optimized (Basic Event Hub, Consumption Function)

---

## When to Use Each Template

### Use **BlobForwarder** when:
- ✅ You already have logs in a storage account
- ✅ You want minimal new infrastructure
- ✅ You need to forward arbitrary blob-based logs
- ✅ You require private network isolation
- ✅ Example: NSG Flow Logs already stored in a container

### Use **EventHubForwarder** when:
- ✅ You want to collect Azure Activity Logs
- ✅ You need to forward diagnostic logs from multiple resources
- ✅ You require high throughput/scaling (Premium plan)
- ✅ You already use Event Hub for centralized logging
- ✅ Example: Centralized platform logs for entire subscription

### Use **VNet Flow Logs** template when:
- ✅ You want to **test VNet Flow Logs from scratch**
- ✅ You need a **complete POC/spike setup**
- ✅ You want to use the new **VNet-level flow logs** (not NSG)
- ✅ You don't have existing infrastructure
- ✅ You want an **end-to-end automated deployment**
- ✅ Example: Quick VNet Flow Logs spike for evaluation

---

## Migration Path

### From NSG Flow Logs (BlobForwarder) → VNet Flow Logs (New Template)

**Why migrate?**
- Azure blocked creation of **new NSG flow logs** starting June 30, 2025
- NSG flow logs will be **retired September 30, 2027**
- VNet flow logs overcome NSG limitations

**Steps:**
1. Deploy new VNet Flow Logs infrastructure using `azuredeploy-vnetflowlogs-complete.json`
2. VNet flow logs will start generating PT1H.json files
3. Gradually migrate monitoring to new pipeline
4. Keep old BlobForwarder running for existing NSG flow logs until retirement
5. Delete old infrastructure after migration complete

**Migration Guide:** https://learn.microsoft.com/en-us/azure/network-watcher/nsg-flow-logs-migrate

---

## Cost Comparison

| Component | BlobForwarder | EventHubForwarder (Basic) | EventHubForwarder (Enterprise) | VNet Flow Logs |
|-----------|---------------|---------------------------|-------------------------------|----------------|
| **Function App** | ~$0/month (Consumption) | ~$0/month (Consumption) | ~$146/month (EP1 Premium) | ~$0/month (Consumption) |
| **Storage Account** | Uses existing | ~$20/month | ~$20/month | ~$20/month (new) |
| **Event Hub** | N/A | ~$11/month (Standard) | ~$11/month (Standard) | **~$0.015/month (Basic)** |
| **Event Grid** | ~$0.60/month | N/A | N/A | ~$0.60/month |
| **VNet/NSG** | Optional (~$0) | N/A | N/A | ~$0 (no egress yet) |
| **Flow Logs** | N/A | N/A | N/A | ~$0.60/GB ingested |
| **Total (approx)** | ~$1-20/month | ~$31/month | ~$177/month | **~$21-50/month** |

**Note:** Costs vary based on:
- Function execution count
- Storage usage
- Event Hub throughput
- Flow logs volume
- Data retention settings

---

## Technical Implementation Differences

### Event Filtering

| Template | Filter Type | Filter Details |
|----------|-------------|----------------|
| **BlobForwarder** | None (Event Grid) | Triggers on all blob creates in container |
| **EventHubForwarder** | None (Event Hub) | Processes all Event Hub messages |
| **VNet Flow Logs** | **Event Grid Advanced** | `subjectEndsWith: "PT1H.json"` + `BlobCreated` event type |

**VNet Flow Logs** uses Event Grid's advanced filtering to ensure only flow log files (PT1H.json) trigger the function.

### Function Code Deployment

| Template | Deployment Method |
|----------|------------------|
| **BlobForwarder** | `WEBSITE_RUN_FROM_PACKAGE` = GitHub releases URL |
| **EventHubForwarder** | `WEBSITE_RUN_FROM_PACKAGE` = GitHub releases URL |
| **VNet Flow Logs** | `WEBSITE_RUN_FROM_PACKAGE` = GitHub releases URL |

All templates use the same deployment artifact: `https://github.com/newrelic/newrelic-azure-functions/releases/latest/download/LogForwarder.zip`

**Manual deployment required:** After ARM template deployment, you must deploy the actual function code separately if you need a specific version or custom code.

### Role-Based Access Control (RBAC)

| Template | RBAC Configuration |
|----------|-------------------|
| **BlobForwarder** | Managed Identity + Storage Blob Data Reader role on **target** storage |
| **EventHubForwarder** | Managed Identity + Event Hubs Data Receiver role |
| **VNet Flow Logs** | Managed Identity + Storage Blob Data Reader role on **source** storage |

All templates use **System-assigned Managed Identity** for secure, passwordless authentication.

---

## Deployment Scripts

### BlobForwarder
- No custom script provided
- Use Azure CLI or Portal with parameter file

### EventHubForwarder
- No custom script provided
- Use Azure CLI or Portal with parameter file

### VNet Flow Logs (New)
- ✅ **deploy-complete.sh** - Automated deployment with validation
- ✅ **diagnose-pipeline.sh** - Full pipeline diagnostics
- ✅ Pre-configured parameters file
- ✅ Validates resource group naming (bpavan- prefix)
- ✅ Comprehensive documentation (COMPLETE_DEPLOYMENT_GUIDE.md, IDEMPOTENCY.md, GENERATE_TRAFFIC.md)

---

## Documentation Comparison

| Template | Documentation |
|----------|---------------|
| **BlobForwarder** | Basic README in repo root |
| **EventHubForwarder** | Basic README in repo root |
| **VNet Flow Logs** | **Comprehensive spike documentation:**<br>• COMPLETE_DEPLOYMENT_GUIDE.md<br>• IDEMPOTENCY.md<br>• GENERATE_TRAFFIC.md<br>• TEMPLATE_COMPARISON.md<br>• README.md<br>• ARM_DEPLOYMENT_GUIDE.md<br>• DEPLOY_CODE.md |

**VNet Flow Logs spike includes extensive documentation** covering every aspect from deployment to troubleshooting.

---

## Summary Table

| Aspect | BlobForwarder | EventHubForwarder | VNet Flow Logs (New) |
|--------|---------------|-------------------|----------------------|
| **Complexity** | Low | High | Medium |
| **Use Case** | Forward existing blob logs | Platform logs via Event Hub | VNet Flow Logs end-to-end |
| **Infrastructure Created** | Minimal | Medium | **Complete** |
| **Setup Time** | 5 minutes | 10 minutes | **5-10 minutes** |
| **Ongoing Cost** | Low ($1-20) | Medium ($31) or High ($177) | **Medium ($21-50)** |
| **Activity Logs** | ❌ No | ✅ Yes | ❌ No |
| **Private VNet** | ✅ Yes (optional) | ❌ No | ❌ No |
| **Premium Scaling** | ❌ No | ✅ Yes (optional) | ❌ No |
| **VNet Flow Logs** | ❌ No | ❌ No | ✅ **Yes** |
| **Idempotent** | ✅ Yes | ✅ Yes | ✅ **Yes** |
| **Documentation** | Basic | Basic | **Comprehensive** |

---

## Key Takeaways

1. **BlobForwarder** = Simple, minimal, works with existing storage
2. **EventHubForwarder** = Feature-rich, Activity Logs support, enterprise scaling
3. **VNet Flow Logs** = Complete infrastructure, spike-ready, modern VNet flow logs

**VNet Flow Logs template is purpose-built for:**
- Quick POC/spike scenarios
- Testing VNet-level flow logs (new Azure standard)
- End-to-end automated deployment
- Cost-optimized infrastructure
- Learning and experimentation

**Future consideration:** After spike validation, you could refactor to use **BlobForwarder** with the existing flow logs storage account for a simpler production setup.

---

## Next Steps

### For VNet Flow Logs Spike Users:
1. ✅ Complete infrastructure is deployed
2. ✅ Pipeline is validated (logs in New Relic)
3. 📝 Document learnings
4. 🔄 Consider production requirements (scaling, cost, security)
5. 🚀 Decide: Continue with this setup or migrate to BlobForwarder for simpler maintenance

### For Production Deployment:
- Consider **EventHubForwarder** if you need Activity Logs + VNet Flow Logs
- Consider **BlobForwarder** if you only need flow logs and want simpler infrastructure
- Consider **VNet Flow Logs template** as a starting point, then customize for your needs
