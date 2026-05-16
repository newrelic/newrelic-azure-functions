# MVP Plan: VNet Flow Logs Forwarder

## Goal
Get the minimum end-to-end flow working to validate the architecture:
- Event Grid detects blob updates
- Function processes events
- Extracts delta (new blocks only)
- Sends to New Relic

---

## MVP Scope (Week 1)

### Phase 1: Simplified ARM Template (Day 1 - 4 hours)

**Resources to Deploy**:
```
✅ Event Hub Namespace + Event Hub + Consumer Group
✅ Event Grid System Topic + Subscription (with filters)
✅ Storage Account (for Function internal state)
✅ App Service Plan (Consumption Y1)
✅ Function App (with Managed Identity)
❌ Skip: Private VNet (not needed for MVP)
❌ Skip: Enterprise scaling (use Basic/Consumption)
❌ Skip: Multiple parameter options (use defaults)
```

**Simplifications**:
- No private VNet deployment option
- No scaling mode option (always Consumption)
- Hardcoded batch sizes (20 events)
- Source storage account must exist (no creation)

**Deliverable**: `azuredeploy-vnetflowlogs-mvp.json` (~400 lines vs 875)

---

### Phase 2: Manual Resource Setup (Day 1 - 2 hours)

Instead of ARM template, create resources manually for fastest iteration:

```bash
# Variables
RG="vnetflowlogs-mvp-rg"
LOCATION="eastus"
SOURCE_STORAGE="existingstorageaccount"  # Your Network Watcher storage
NR_LICENSE_KEY="your-license-key"

# 1. Create Resource Group
az group create --name $RG --location $LOCATION

# 2. Create Event Hub Namespace + Event Hub
az eventhubs namespace create \
  --name vnetflowlogs-eventhub-ns \
  --resource-group $RG \
  --location $LOCATION \
  --sku Standard

az eventhubs eventhub create \
  --name vnetflowlogs-eventhub \
  --resource-group $RG \
  --namespace-name vnetflowlogs-eventhub-ns \
  --partition-count 4 \
  --message-retention 1

az eventhubs consumergroup create \
  --name vnetflowlogs-consumer \
  --resource-group $RG \
  --namespace-name vnetflowlogs-eventhub-ns \
  --eventhub-name vnetflowlogs-eventhub

# 3. Create Storage Account (for Function state)
az storage account create \
  --name vnetflowlogsmvp$(date +%s | tail -c 5) \
  --resource-group $RG \
  --location $LOCATION \
  --sku Standard_LRS

# Save storage name
INTERNAL_STORAGE=$(az storage account list -g $RG --query "[0].name" -o tsv)

# 4. Create Function App
az functionapp create \
  --name vnetflowlogs-function-mvp \
  --resource-group $RG \
  --storage-account $INTERNAL_STORAGE \
  --consumption-plan-location $LOCATION \
  --runtime node \
  --runtime-version 22 \
  --functions-version 4 \
  --assign-identity

# 5. Get Event Hub connection string
EVENTHUB_CONN=$(az eventhubs namespace authorization-rule keys list \
  --resource-group $RG \
  --namespace-name vnetflowlogs-eventhub-ns \
  --name RootManageSharedAccessKey \
  --query primaryConnectionString -o tsv)

# 6. Configure Function App
az functionapp config appsettings set \
  --name vnetflowlogs-function-mvp \
  --resource-group $RG \
  --settings \
    EVENTHUB_NAME=vnetflowlogs-eventhub \
    EVENTHUB_CONSUMER_CONNECTION="$EVENTHUB_CONN" \
    EVENTHUB_CONSUMER_GROUP=vnetflowlogs-consumer \
    NR_LICENSE_KEY="$NR_LICENSE_KEY" \
    NR_ENDPOINT=https://log-api.newrelic.com/log/v1 \
    VNETFLOWLOGS_FORWARDER_ENABLED=true \
    SOURCE_STORAGE_ACCOUNT_NAME=$SOURCE_STORAGE

# 7. Create Event Grid System Topic
az eventgrid system-topic create \
  --name vnetflowlogs-egtopic \
  --resource-group $RG \
  --location $LOCATION \
  --topic-type Microsoft.Storage.StorageAccounts \
  --source /subscriptions/$(az account show --query id -o tsv)/resourceGroups/SOURCE_RG/providers/Microsoft.Storage/storageAccounts/$SOURCE_STORAGE

# 8. Create Event Grid Subscription
az eventgrid system-topic event-subscription create \
  --name vnetflowlogs-egsub \
  --resource-group $RG \
  --system-topic-name vnetflowlogs-egtopic \
  --endpoint-type eventhub \
  --endpoint /subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RG/providers/Microsoft.EventHub/namespaces/vnetflowlogs-eventhub-ns/eventhubs/vnetflowlogs-eventhub \
  --included-event-types Microsoft.Storage.BlobCreated \
  --subject-ends-with PT1H.json \
  --advanced-filter subject StringContains insights-logs-flowlogflowevent

# 9. Grant Function App read access to source storage
PRINCIPAL_ID=$(az functionapp identity show \
  --name vnetflowlogs-function-mvp \
  --resource-group $RG \
  --query principalId -o tsv)

az role assignment create \
  --assignee $PRINCIPAL_ID \
  --role "Storage Blob Data Reader" \
  --scope /subscriptions/$(az account show --query id -o tsv)/resourceGroups/SOURCE_RG/providers/Microsoft.Storage/storageAccounts/$SOURCE_STORAGE

echo "✅ MVP Infrastructure Ready!"
echo "Function App: vnetflowlogs-function-mvp"
echo "Event Hub: vnetflowlogs-eventhub"
```

**Time**: ~15 minutes to run

---

### Phase 3: Minimal Function Code (Day 2-3 - 2 days)

**MVP Function Features**:
```
✅ Register Event Hub trigger
✅ Parse Event Grid blob event
✅ Download ENTIRE blob (skip delta extraction for MVP)
✅ Parse VNet Flow Logs JSON
✅ Send to New Relic
❌ Skip: Table Storage cursor management
❌ Skip: Delta extraction (download full file for now)
❌ Skip: Error handling (basic only)
❌ Skip: Retry logic (use built-in)
```

**File Structure**:
```
LogForwarder/
├── index.js              # Main entry point (modify)
├── vnetFlowLogsHandler.js  # New file (MVP logic)
├── package.json          # Add dependencies
└── lib/
    └── common.js         # Existing (reuse for NR sending)
```

#### Step 3.1: Add Dependencies

```json
// package.json - Add these dependencies
{
  "dependencies": {
    "@azure/functions": "^4.0.0",
    "@azure/identity": "^4.0.0",
    "@azure/storage-blob": "^12.17.0",
    "axios": "^1.6.0"
  }
}
```

#### Step 3.2: Create MVP Handler

```javascript
// LogForwarder/vnetFlowLogsHandler.js

const { BlobServiceClient } = require('@azure/storage-blob');
const { DefaultAzureCredential } = require('@azure/identity');
const axios = require('axios');

async function handleVNetFlowLogs(eventGridMessages, context) {
  context.log(`[VNetFlowLogs] Processing ${eventGridMessages.length} Event Grid events`);

  for (const event of eventGridMessages) {
    try {
      // 1. Parse Event Grid blob event
      const blobUrl = event.data.url; // Full blob URL
      context.log(`[VNetFlowLogs] Processing blob: ${blobUrl}`);

      // 2. Download blob using Managed Identity (MVP: download entire blob)
      const credential = new DefaultAzureCredential();
      const blobClient = new BlobServiceClient(blobUrl, credential).getBlobClient('');

      const downloadResponse = await blobClient.download(0);
      const blobContent = await streamToString(downloadResponse.readableStreamBody);

      context.log(`[VNetFlowLogs] Downloaded ${blobContent.length} bytes`);

      // 3. Parse VNet Flow Logs JSON
      const flowLogsData = JSON.parse(blobContent);
      const records = flowLogsData.records || [];

      context.log(`[VNetFlowLogs] Parsed ${records.length} flow log records`);

      if (records.length === 0) {
        context.log('[VNetFlowLogs] No records to send');
        continue;
      }

      // 4. Transform to New Relic format
      const nrLogs = records.map(record => ({
        timestamp: new Date(record.time).getTime(),
        message: 'Azure VNet Flow Log',
        logtype: 'azure.vnet.flowlog',
        ...flattenFlowRecord(record)
      }));

      // 5. Send to New Relic
      await sendToNewRelic(nrLogs, context);

      context.log(`[VNetFlowLogs] Successfully sent ${nrLogs.length} logs to New Relic`);

    } catch (error) {
      context.log.error(`[VNetFlowLogs] Error processing event: ${error.message}`);
      // MVP: Log error but don't throw (continue with next event)
    }
  }
}

// Helper: Convert stream to string
async function streamToString(readableStream) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    readableStream.on('data', (data) => {
      chunks.push(data.toString());
    });
    readableStream.on('end', () => {
      resolve(chunks.join(''));
    });
    readableStream.on('error', reject);
  });
}

// Helper: Flatten nested flow record structure
function flattenFlowRecord(record) {
  const flattened = {
    time: record.time,
    systemId: record.systemId,
    macAddress: record.macAddress,
    category: record.category,
    resourceId: record.resourceId,
    operationName: record.operationName
  };

  // Flatten flows array
  if (record.flows && record.flows.length > 0) {
    const flow = record.flows[0]; // MVP: Take first flow
    flattened.rule = flow.rule;

    if (flow.flows && flow.flows.length > 0) {
      const innerFlow = flow.flows[0];
      flattened.flowState = innerFlow.flowState;

      if (innerFlow.flowTuples && innerFlow.flowTuples.length > 0) {
        // Parse flow tuple: timestamp,sourceIP,destIP,sourcePort,destPort,protocol,direction,decision
        const tuple = innerFlow.flowTuples[0].split(',');
        flattened.sourceIP = tuple[1];
        flattened.destIP = tuple[2];
        flattened.sourcePort = tuple[3];
        flattened.destPort = tuple[4];
        flattened.protocol = tuple[5];
        flattened.direction = tuple[6];
        flattened.decision = tuple[7];
      }
    }
  }

  return flattened;
}

// Helper: Send to New Relic
async function sendToNewRelic(logs, context) {
  const endpoint = process.env.NR_ENDPOINT || 'https://log-api.newrelic.com/log/v1';
  const licenseKey = process.env.NR_LICENSE_KEY;

  if (!licenseKey) {
    throw new Error('NR_LICENSE_KEY not configured');
  }

  const payload = [{
    common: {
      attributes: {
        plugin: 'azure-vnet-flowlogs-forwarder',
        version: '1.0.0-mvp'
      }
    },
    logs: logs
  }];

  await axios.post(endpoint, payload, {
    headers: {
      'Content-Type': 'application/json',
      'X-License-Key': licenseKey
    }
  });
}

module.exports = { handleVNetFlowLogs };
```

#### Step 3.3: Register Trigger in index.js

```javascript
// LogForwarder/index.js - Add this

const { app } = require('@azure/functions');
const { handleVNetFlowLogs } = require('./vnetFlowLogsHandler');

// Existing triggers...
// (EventHubForwarder, BlobForwarder)

// NEW: VNet Flow Logs Forwarder
if (process.env.VNETFLOWLOGS_FORWARDER_ENABLED === 'true') {
  app.eventHub('VNetFlowLogsForwarder', {
    eventHubName: process.env.EVENTHUB_NAME,
    connection: 'EVENTHUB_CONSUMER_CONNECTION',
    cardinality: 'many',
    consumerGroup: process.env.EVENTHUB_CONSUMER_GROUP || '$Default',
    handler: handleVNetFlowLogs
  });
}
```

#### Step 3.4: Deploy Function Code

```bash
# Package the function
cd LogForwarder
npm install
cd ..
zip -r LogForwarder-mvp.zip LogForwarder/ host.json package.json

# Deploy to Function App
az functionapp deployment source config-zip \
  --name vnetflowlogs-function-mvp \
  --resource-group $RG \
  --src LogForwarder-mvp.zip
```

**Time**: 2 days for code + testing

---

### Phase 4: E2E Validation (Day 3 - 2 hours)

#### Test 1: Trigger Event Grid Manually

```bash
# Upload a test blob to source storage
echo '{
  "records": [{
    "time": "'$(date -u +%Y-%m-%dT%H:%M:%S.000Z)'",
    "systemId": "test-system",
    "macAddress": "00-0D-3A-92-6A-7C",
    "category": "FlowLogFlowEvent",
    "resourceId": "/subscriptions/test/resourceGroups/test-rg/providers/Microsoft.Network/networkSecurityGroups/test-nsg",
    "operationName": "NetworkSecurityGroupFlowEvents",
    "flows": [{
      "rule": "DefaultRule_AllowInternetOutBound",
      "flows": [{
        "flowState": "B",
        "flowTuples": ["'$(date +%s)',10.0.0.4,20.40.60.80,35678,443,T,O,A"]
      }]
    }]
  }]
}' > /tmp/test-flowlog.json

az storage blob upload \
  --account-name $SOURCE_STORAGE \
  --container-name insights-logs-flowlogflowevent \
  --name "resourceId=/SUBSCRIPTIONS/test/RESOURCEGROUPS/test-rg/PROVIDERS/MICROSOFT.NETWORK/NETWORKSECURITYGROUPS/test-nsg/y=$(date +%Y)/m=$(date +%m)/d=$(date +%d)/h=$(date +%H)/m=00/macAddress=00-0D-3A-92-6A-7C/PT1H.json" \
  --file /tmp/test-flowlog.json \
  --overwrite
```

#### Test 2: Monitor Function Logs

```bash
# Watch Function logs in real-time
az webapp log tail --name vnetflowlogs-function-mvp --resource-group $RG

# Expected output:
# [VNetFlowLogs] Processing 1 Event Grid events
# [VNetFlowLogs] Processing blob: https://...PT1H.json
# [VNetFlowLogs] Downloaded 450 bytes
# [VNetFlowLogs] Parsed 1 flow log records
# [VNetFlowLogs] Successfully sent 1 logs to New Relic
```

#### Test 3: Verify in New Relic

```bash
# Query New Relic Logs (via New Relic CLI or UI)
newrelic nrql query --accountId YOUR_ACCOUNT_ID --query "
  SELECT * FROM Log
  WHERE logtype = 'azure.vnet.flowlog'
  SINCE 10 minutes ago
"

# Or in New Relic UI:
# https://one.newrelic.com/logger
# Query: logtype:azure.vnet.flowlog
```

**Expected Result**: See the flow log record with fields:
- `sourceIP: 10.0.0.4`
- `destIP: 20.40.60.80`
- `sourcePort: 35678`
- `destPort: 443`
- `protocol: T` (TCP)
- `macAddress: 00-0D-3A-92-6A-7C`

---

## What We're Skipping in MVP (Add Later)

### Not in MVP:
1. ❌ **Delta Extraction** (Table Storage cursor)
   - MVP downloads entire blob each time
   - Will cause duplication until we add state management
   - **Add in Phase 2** (Week 2)

2. ❌ **Private VNet Support**
   - Use public endpoints for MVP
   - **Add in Phase 3** (Week 3)

3. ❌ **Advanced Error Handling**
   - Basic try/catch only
   - No dead letter queue
   - **Add in Phase 2**

4. ❌ **Performance Optimization**
   - No batching optimization
   - No parallel processing
   - **Add in Phase 3**

5. ❌ **Comprehensive Testing**
   - Manual testing only
   - **Add unit tests in Phase 2**
   - **Add integration tests in Phase 3**

6. ❌ **Enterprise Scaling**
   - Use Consumption plan only
   - **Add Premium plan option in Phase 3**

---

## MVP Success Criteria

### ✅ MVP is successful if:
1. Event Grid detects blob updates (PT1H.json files only)
2. Events route to Event Hub
3. Function triggers on Event Hub events
4. Function downloads blob using Managed Identity
5. Function parses VNet Flow Logs JSON
6. Logs appear in New Relic with correct format

### ⚠️ Known MVP Limitations:
- Will download entire blob (not delta) → temporary duplication
- No state persistence (cursor tracking)
- Minimal error handling
- No comprehensive testing

---

## Timeline

| Phase | Task | Time | Deliverable |
|-------|------|------|-------------|
| **Day 1** | Manual infrastructure setup | 4 hours | Working Event Grid → Event Hub → Function |
| **Day 2** | MVP function code | 8 hours | Basic handler that downloads full blob |
| **Day 3** | E2E testing & validation | 4 hours | Logs flowing to New Relic |
| **TOTAL** | **MVP Complete** | **2-3 days** | ✅ **E2E Validated** |

---

## Post-MVP: Phase 2 (Week 2)

Once MVP is validated, add:
1. **Table Storage State Management** (1 day)
   - Track last processed block count
   - Implement cursor read/write

2. **Delta Extraction** (1 day)
   - Use block list API
   - Download only new blocks
   - Eliminate duplication

3. **Error Handling** (1 day)
   - Retry logic
   - Dead letter queue
   - Monitoring/alerts

**Time**: 3 days

---

## Post-MVP: Phase 3 (Week 3)

Production readiness:
1. **Private VNet Support** (1 day)
2. **Enterprise Scaling** (1 day)
3. **Comprehensive Testing** (2 days)
4. **Documentation** (1 day)

**Time**: 5 days

---

## Total Timeline

- **MVP (E2E Validated)**: 2-3 days
- **Phase 2 (Delta + State)**: 3 days
- **Phase 3 (Production Ready)**: 5 days
- **TOTAL**: **10-11 days**

---

## Quick Start: Run MVP Today

```bash
# 1. Clone the repo
cd /Users/bpavan/repos/logint/nr/newrelic-azure-functions

# 2. Run manual setup script (copy commands from Phase 2)
bash scripts/setup-mvp.sh

# 3. Create vnetFlowLogsHandler.js (copy code from Phase 3)
# 4. Modify index.js to register trigger
# 5. Deploy function code
# 6. Test with sample blob upload

# Expected time: 4-6 hours total
```

---

## Decision: ARM Template or Manual?

### Option A: Manual Setup (Recommended for MVP)
- ✅ Faster iteration (15 minutes vs 2 hours)
- ✅ Easier to debug
- ✅ Can skip VNet complexity
- ❌ Not repeatable

### Option B: Simplified ARM Template
- ✅ Repeatable deployment
- ✅ Production-ready foundation
- ❌ Slower initial setup
- ❌ Harder to debug

**Recommendation**: Start with **Manual Setup** for MVP, then create ARM template after validation.
