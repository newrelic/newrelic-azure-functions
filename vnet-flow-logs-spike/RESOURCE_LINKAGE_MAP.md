# Resource Linkage Map: VNet Flow Logs Forwarder

## Quick Visual Reference

This diagram shows **what links to what** and **how to configure the connections**.

---

## 🎯 The 5 Resources You'll Create

```
1️⃣ Storage Account (Internal)          "vnetflowlogsmvp12345"
2️⃣ Event Hub Namespace + Event Hub     "vnetflowlogs-eventhub-ns"
3️⃣ Function App                        "vnetflowlogs-function"
4️⃣ Event Grid System Topic             "vnetflowlogs-egtopic"
5️⃣ Event Grid Event Subscription       "vnetflowlogs-egsub"
```

---

## 🔗 Linkage Map

```
┌─────────────────────────────────────────────────────────────────┐
│                    PREREQUISITE (Existing)                      │
│                                                                 │
│  Source Storage Account: "yournetworkwatcherstorage"           │
│  └── Container: insights-logs-flowlogflowevent                 │
│      └── Blobs: .../PT1H.json                                  │
└────────────────┬────────────────────────────────────────────────┘
                 │
                 │ ❶ LINKED VIA: Event Grid System Topic
                 │    Configuration: "Source Resource" = this storage
                 ↓
┌─────────────────────────────────────────────────────────────────┐
│  4️⃣ Event Grid System Topic: "vnetflowlogs-egtopic"           │
│                                                                 │
│  Config:                                                        │
│  - Topic Type: Storage Accounts                                │
│  - Source Resource: [Your source storage account]              │
└────────────────┬────────────────────────────────────────────────┘
                 │
                 │ ❷ LINKED VIA: Event Grid Event Subscription
                 │    Configuration: Created under this system topic
                 ↓
┌─────────────────────────────────────────────────────────────────┐
│  5️⃣ Event Grid Event Subscription: "vnetflowlogs-egsub"       │
│                                                                 │
│  Config:                                                        │
│  - Endpoint Type: Event Hubs                                   │
│  - Event Hub Namespace: vnetflowlogs-eventhub-ns              │
│  - Event Hub: vnetflowlogs-eventhub                           │
│  - Filters:                                                    │
│    • Subject Ends With: PT1H.json                             │
│    • Subject Contains: insights-logs-flowlogflowevent         │
└────────────────┬────────────────────────────────────────────────┘
                 │
                 │ ❸ LINKED VIA: Event Hub Endpoint
                 │    Configuration: Endpoint points to Event Hub
                 ↓
┌─────────────────────────────────────────────────────────────────┐
│  2️⃣ Event Hub: "vnetflowlogs-eventhub"                        │
│     (inside "vnetflowlogs-eventhub-ns")                        │
│                                                                 │
│  Config:                                                        │
│  - Partition Count: 4                                          │
│  - Message Retention: 1 day                                    │
│  - Consumer Group: vnetflowlogs-consumer                       │
└────────────────┬────────────────────────────────────────────────┘
                 │
                 │ ❹ LINKED VIA: Function App Configuration
                 │    Configuration: EVENTHUB_CONSUMER_CONNECTION
                 ↓
┌─────────────────────────────────────────────────────────────────┐
│  3️⃣ Function App: "vnetflowlogs-function"                     │
│                                                                 │
│  Config (App Settings):                                         │
│  - EVENTHUB_NAME = vnetflowlogs-eventhub                      │
│  - EVENTHUB_CONSUMER_CONNECTION = [connection string]          │
│  - EVENTHUB_CONSUMER_GROUP = vnetflowlogs-consumer            │
│  - SOURCE_STORAGE_ACCOUNT_NAME = [your source storage]        │
│  - NR_LICENSE_KEY = [your license key]                        │
│  - VNETFLOWLOGS_FORWARDER_ENABLED = true                      │
│                                                                 │
│  Identity:                                                      │
│  - System Assigned Managed Identity: ON                        │
└────────────────┬────────────────────────────────────────────────┘
                 │
                 │ ❺ LINKED VIA: Managed Identity RBAC
                 │    Configuration: Storage Blob Data Reader role
                 ↓
┌─────────────────────────────────────────────────────────────────┐
│  Source Storage Account (back to top)                          │
│                                                                 │
│  Access Control (IAM):                                         │
│  - Role: Storage Blob Data Reader                             │
│  - Assigned to: vnetflowlogs-function (Managed Identity)      │
└─────────────────────────────────────────────────────────────────┘
                 │
                 │ ❻ Function Reads & Sends
                 ↓
           New Relic Logs API
```

---

## 📋 Connection Details

### Connection 1: Event Grid → Source Storage
**Type**: System Topic
**Where to Configure**: Event Grid System Topic creation
**Key Setting**: "Source Resource" dropdown
**What it does**: Monitors source storage for blob events

---

### Connection 2: Event Subscription → System Topic
**Type**: Parent-Child
**Where to Configure**: Create Event Subscription under System Topic
**Key Setting**: System Topic is automatically selected
**What it does**: Defines filtering and routing rules

---

### Connection 3: Event Subscription → Event Hub
**Type**: Endpoint Configuration
**Where to Configure**: Event Subscription → "Endpoint Details"
**Key Settings**:
```
Endpoint Type: Event Hubs
Event Hub Namespace: vnetflowlogs-eventhub-ns
Event Hub: vnetflowlogs-eventhub
```
**What it does**: Routes filtered events to Event Hub

---

### Connection 4: Function App → Event Hub
**Type**: App Configuration (Connection String)
**Where to Configure**: Function App → Configuration → Application Settings
**Key Settings**:
```
EVENTHUB_NAME = vnetflowlogs-eventhub
EVENTHUB_CONSUMER_CONNECTION = Endpoint=sb://vnetflowlogs-eventhub-ns...
EVENTHUB_CONSUMER_GROUP = vnetflowlogs-consumer
```
**What it does**: Function listens to Event Hub for new events

**How to get connection string**:
1. Go to Event Hub Namespace (not the Event Hub itself)
2. Click "Shared access policies"
3. Click "RootManageSharedAccessKey"
4. Copy "Connection string–primary key"

---

### Connection 5: Function App → Source Storage
**Type**: Managed Identity + RBAC
**Where to Configure**: Two places:

**Part A - Enable Managed Identity**:
1. Function App → Identity → System assigned → Status = On

**Part B - Grant Permission**:
1. Source Storage Account → Access Control (IAM) → Add role assignment
2. Role: Storage Blob Data Reader
3. Assign to: Managed Identity → Function App → vnetflowlogs-function

**What it does**: Allows Function to read blobs from source storage

---

### Connection 6: Function App → Internal Storage
**Type**: Automatic (built-in)
**Where to Configure**: Function App creation (storage selection)
**Key Setting**: Storage account dropdown
**What it does**: Function uses this for state, logs, and Table Storage

---

### Connection 7: Function App → New Relic
**Type**: App Configuration (API Key)
**Where to Configure**: Function App → Configuration → Application Settings
**Key Settings**:
```
NR_LICENSE_KEY = your-new-relic-license-key
NR_ENDPOINT = https://log-api.newrelic.com/log/v1
```
**What it does**: Function sends logs to New Relic

---

## 🔍 How to Find Each Configuration

| What You Need | Where to Find It | How to Get It |
|---------------|------------------|---------------|
| **Event Hub Connection String** | Event Hub Namespace → Shared access policies → RootManageSharedAccessKey | Copy "Connection string–primary key" |
| **Function Managed Identity ID** | Function App → Identity → System assigned | Copy "Object (principal) ID" |
| **Source Storage Resource ID** | Source Storage → Properties | Copy "Resource ID" |
| **Event Hub Resource ID** | Event Hub → Properties | Copy "Resource ID" (needed for Event Grid endpoint) |
| **Storage Account Key** | Storage Account → Access keys | NOT NEEDED (using Managed Identity) |

---

## 🎬 Configuration Order

Follow this order to avoid dependency issues:

```
Step 1: Create Storage Account (Internal)
         └── Note: Name (e.g., vnetflowlogsmvp12345)

Step 2: Create Event Hub Namespace + Event Hub
         └── Copy: Connection String from Namespace

Step 3: Create Function App
         ├── Select: Storage Account from Step 1
         ├── Enable: Managed Identity
         └── Add: App Settings (use connection string from Step 2)

Step 4: Create Event Grid System Topic
         └── Select: Source Storage Account (your existing one)

Step 5: Create Event Grid Event Subscription
         ├── Parent: System Topic from Step 4
         ├── Endpoint: Event Hub from Step 2
         └── Add: Filters (PT1H.json, insights-logs-flowlogflowevent)

Step 6: Grant Function App Access to Source Storage
         ├── Navigate: Source Storage → IAM
         ├── Role: Storage Blob Data Reader
         └── Assignee: Function Managed Identity from Step 3
```

---

## 🧪 Testing the Linkages

### Test 1: Event Grid → Event Hub
**Action**: Upload a PT1H.json file to source storage
**Check**: Event Hub → Metrics → "Incoming Messages" should increase
**If not working**: Check Event Grid filters

### Test 2: Event Hub → Function
**Action**: Wait for an event in Event Hub
**Check**: Function App → Monitor → Should see invocations
**If not working**: Check Function App settings (connection string)

### Test 3: Function → Source Storage
**Action**: Function triggers
**Check**: Function logs should show "Downloaded X bytes"
**If not working**: Check IAM role assignment (Storage Blob Data Reader)

### Test 4: Function → New Relic
**Action**: Function processes event
**Check**: New Relic → Logs → Query for "azure.vnet.flowlog"
**If not working**: Check NR_LICENSE_KEY and NR_ENDPOINT

---

## 📝 Quick Checklist

Use this to verify all linkages are correct:

```
✅ Storage Account (Internal) created
   └── ✅ Name noted down

✅ Event Hub Namespace created
   └── ✅ Event Hub created inside namespace
       └── ✅ Consumer Group created
           └── ✅ Connection string copied

✅ Function App created
   ├── ✅ Storage Account linked (from Step 1)
   ├── ✅ Managed Identity enabled
   └── ✅ App Settings configured:
       ├── ✅ EVENTHUB_NAME
       ├── ✅ EVENTHUB_CONSUMER_CONNECTION
       ├── ✅ EVENTHUB_CONSUMER_GROUP
       ├── ✅ NR_LICENSE_KEY
       ├── ✅ NR_ENDPOINT
       ├── ✅ VNETFLOWLOGS_FORWARDER_ENABLED
       └── ✅ SOURCE_STORAGE_ACCOUNT_NAME

✅ Event Grid System Topic created
   └── ✅ Linked to source storage account

✅ Event Grid Event Subscription created
   ├── ✅ Parent = System Topic
   ├── ✅ Endpoint = Event Hub
   └── ✅ Filters configured:
       ├── ✅ Subject Ends With: PT1H.json
       └── ✅ Subject Contains: insights-logs-flowlogflowevent

✅ RBAC Role assigned
   ├── ✅ Resource: Source Storage Account
   ├── ✅ Role: Storage Blob Data Reader
   └── ✅ Assignee: Function App Managed Identity

✅ Function Code deployed
   └── ✅ VNetFlowLogsForwarder function appears in portal
```

---

## 🚨 Common Mistakes

### Mistake 1: Wrong Storage Account
- ❌ Linking Event Grid System Topic to **internal storage** (wrong!)
- ✅ Should link to **source storage** (where Network Watcher writes)

### Mistake 2: Wrong Connection String
- ❌ Using Event Hub connection string (from Event Hub itself)
- ✅ Should use Namespace connection string (from Event Hub **Namespace**)

### Mistake 3: Missing Managed Identity
- ❌ Forgetting to enable System Assigned Managed Identity
- ✅ Must enable in Function App → Identity before assigning RBAC

### Mistake 4: Wrong RBAC Scope
- ❌ Assigning role at subscription or resource group level
- ✅ Should assign at storage account level (specific resource)

### Mistake 5: Filters Too Broad
- ❌ Not filtering for PT1H.json → processes all blobs
- ✅ Must add both filters (ends with PT1H.json AND contains insights-logs-flowlogflowevent)

---

## 💡 Pro Tips

1. **Keep Names Consistent**: Use same prefix for all resources (e.g., `vnetflowlogs-*`)

2. **Use Same Region**: Deploy all resources in the same Azure region for lower latency

3. **Copy Values Immediately**: When creating resources, copy connection strings, IDs, etc. immediately

4. **Test Each Link**: After creating each linkage, test it before moving to the next

5. **Use Resource Groups**: Keep all resources in same Resource Group for easy management/cleanup

6. **Enable Logging**: Turn on diagnostic logs for troubleshooting

7. **Monitor Costs**: Check Azure Cost Management after 24 hours to verify cost estimates

---

## 📚 Reference

Full step-by-step guide: [MANUAL_UI_SETUP_GUIDE.md](./MANUAL_UI_SETUP_GUIDE.md)