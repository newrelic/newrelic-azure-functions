# Complete Setup Overview: VNet Flow Logs to New Relic

## End-to-End Architecture

This document shows the **complete picture** from creating a VNet to getting logs in New Relic.

---

## 🎯 The Complete Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                   STEP 0: PREREQUISITES                         │
│                  (Skip if already exists)                       │
└─────────────────────────────────────────────────────────────────┘

  1. Create Virtual Network (VNet)
     └── 10.0.0.0/16 address space
         └── Subnet: 10.0.0.0/24

  2. Create Network Security Group (NSG)
     └── Associate with VNet subnet

  3. Enable Network Watcher
     └── Auto-enabled in most regions

  4. Create Storage Account (Source)
     └── For storing VNet Flow Logs
         Name: vnetflowlogssource12345

  5. Enable VNet Flow Logs
     └── Target: NSG (demo-nsg)
     └── Destination: Storage Account (vnetflowlogssource12345)
     └── Updates PT1H.json every ~60 seconds

  6. Generate Traffic (optional)
     └── Deploy test VM or make requests
     └── Generates network flow data

  7. Verify Flow Logs
     └── Check: insights-logs-flowlogflowevent/...PT1H.json exists

                        ↓

┌─────────────────────────────────────────────────────────────────┐
│                    DATA GENERATION PHASE                        │
│                  (Happens automatically)                        │
└─────────────────────────────────────────────────────────────────┘

  Network Traffic in VNet
         ↓
  Network Watcher Captures Flows
         ↓
  Writes to: vnetflowlogssource12345/insights-logs-flowlogflowevent/
             .../PT1H.json
         ↓
  Appends new data every ~60 seconds
  (Same file updated 60 times per hour)

                        ↓

┌─────────────────────────────────────────────────────────────────┐
│                 STEPS 1-6: FORWARDER SETUP                      │
│               (What you'll configure)                           │
└─────────────────────────────────────────────────────────────────┘

  Step 1: Create Storage Account (Internal)
     └── vnetflowlogsmvp12345
     └── For Function state + Table Storage cursors

  Step 2: Create Event Hub Namespace + Event Hub
     └── vnetflowlogs-eventhub-ns / vnetflowlogs-eventhub
     └── Acts as message queue

  Step 3: Create Function App
     └── vnetflowlogs-function
     └── Enable Managed Identity
     └── Configure app settings

  Step 4: Create Event Grid System Topic
     └── vnetflowlogs-egtopic
     └── Monitors: vnetflowlogssource12345 (source storage)

  Step 5: Create Event Grid Event Subscription
     └── vnetflowlogs-egsub
     └── Filters: PT1H.json files only
     └── Routes to: Event Hub

  Step 6: Grant RBAC Permissions
     └── Function App → Storage Blob Data Reader
     └── On: vnetflowlogssource12345

                        ↓

┌─────────────────────────────────────────────────────────────────┐
│                    RUNTIME DATA FLOW                            │
│               (Happens automatically)                           │
└─────────────────────────────────────────────────────────────────┘

  1. Network Watcher appends to PT1H.json
         ↓
  2. Storage Account emits BlobCreated event
         ↓
  3. Event Grid System Topic captures event
         ↓
  4. Event Grid Subscription filters event
     (Only PT1H.json in insights-logs-flowlogflowevent)
         ↓
  5. Event routed to Event Hub
     (Partition key = blob file path)
         ↓
  6. Function App triggers on Event Hub event
         ↓
  7. Function reads cursor from Table Storage
     (Last processed block count)
         ↓
  8. Function downloads blob delta
     (Only new blocks since last cursor)
         ↓
  9. Function parses VNet Flow Logs JSON
         ↓
  10. Function sends logs to New Relic API
         ↓
  11. Function updates cursor in Table Storage
         ↓
  12. Logs appear in New Relic!
```

---

## 📊 Resource Inventory

### Prerequisites (Step 0)

| Resource | Example Name | Purpose | Created By |
|----------|--------------|---------|------------|
| Virtual Network | `demo-vnet` | Network infrastructure | You (Step 0A) |
| Network Security Group | `demo-nsg` | Required for flow logs | You (Step 0B) |
| Network Watcher | (auto-named) | Captures network telemetry | Azure (Step 0C) |
| Storage Account (Source) | `vnetflowlogssource12345` | Stores PT1H.json files | You (Step 0D) |
| Flow Logs Config | `demo-nsg-flowlog` | Enables flow logging | You (Step 0E) |
| Virtual Machine | `test-vm` (optional) | Generates traffic | You (Step 0F) |

### Forwarder Components (Steps 1-6)

| Resource | Example Name | Purpose | Created By |
|----------|--------------|---------|------------|
| Storage Account (Internal) | `vnetflowlogsmvp12345` | Function state + cursors | You (Step 1) |
| Event Hub Namespace | `vnetflowlogs-eventhub-ns` | Messaging infrastructure | You (Step 2) |
| Event Hub | `vnetflowlogs-eventhub` | Message queue | You (Step 2) |
| Consumer Group | `vnetflowlogs-consumer` | Function's consumer | You (Step 2) |
| Function App | `vnetflowlogs-function` | Processes events | You (Step 3) |
| Event Grid System Topic | `vnetflowlogs-egtopic` | Monitors source storage | You (Step 4) |
| Event Grid Subscription | `vnetflowlogs-egsub` | Filters & routes events | You (Step 5) |

**Total Resources**: 13 (6 prerequisites + 7 forwarder components)

---

## 🔗 Resource Dependencies

```
Prerequisites (can exist independently):
┌──────────────┐
│ Virtual      │
│ Network      │
└──────┬───────┘
       │
       ├──→ ┌──────────────┐
       │    │ Network      │
       │    │ Security     │
       │    │ Group        │
       │    └──────┬───────┘
       │           │
       │           ├──→ ┌──────────────┐
       │           │    │ Network      │
       │           │    │ Watcher      │
       │           │    └──────┬───────┘
       │           │           │
       │           │           ├──→ ┌──────────────┐
       │           │           │    │ Storage      │
       │           │           │    │ (Source)     │
       │           │           │    └──────┬───────┘
       │           │           │           │
       │           │           └───────────┤
       │           │                       │
       │           └──→ Flow Logs Config ──┘
       │
       └──→ Virtual Machine (optional) ──┘

Forwarder (depends on source storage):
┌──────────────┐
│ Storage      │
│ (Source)     │◄─────┐
└──────┬───────┘      │
       │              │
       ↓              │
┌──────────────┐      │
│ Event Grid   │      │
│ System Topic │      │
└──────┬───────┘      │
       │              │
       ↓              │
┌──────────────┐      │
│ Event Grid   │      │
│ Subscription │      │
└──────┬───────┘      │
       │              │
       ├──→ ┌──────────────┐
       │    │ Event Hub    │
       │    └──────┬───────┘
       │           │
       │           ↓
       │    ┌──────────────┐      ┌──────────────┐
       │    │ Function App │◄─────│ Storage      │
       │    │              │      │ (Internal)   │
       │    └──────────────┘      └──────────────┘
       │           │
       └───────────┘ (Managed Identity reads source)
```

---

## 🕐 Time Estimates

| Phase | Time | Tasks |
|-------|------|-------|
| **Step 0: Prerequisites** | 30-45 min | VNet, NSG, Network Watcher, Storage, Flow Logs, Verify |
| **Step 1: Internal Storage** | 5 min | Create storage account |
| **Step 2: Event Hub** | 10 min | Namespace, Event Hub, Consumer Group, Get connection string |
| **Step 3: Function App** | 15 min | Create function, enable identity, configure settings |
| **Step 4: Event Grid Topic** | 5 min | Create system topic on source storage |
| **Step 5: Event Grid Subscription** | 10 min | Create subscription with filters |
| **Step 6: RBAC Permissions** | 5 min | Grant Function read access to source storage |
| **Step 7: Deploy Code** | 10 min | Deploy function code |
| **Step 8: Testing** | 10 min | Upload test blob, verify logs |
| **Total (from scratch)** | **2-3 hours** | All steps |
| **Total (existing VNet)** | **1-2 hours** | Steps 1-8 only |

---

## 💰 Cost Breakdown

### Prerequisites (Step 0)

| Resource | SKU | Monthly Cost |
|----------|-----|--------------|
| Virtual Network | Free tier | $0 |
| Network Security Group | Free tier | $0 |
| Network Watcher | Per GB processed | ~$0.50-2/GB (typical: $5-10/month) |
| Storage Account (Source) | Standard LRS | ~$20/TB (typical: $2-5/month for flow logs) |
| Virtual Machine | B1s (optional) | $10/month |
| **Subtotal (Prerequisites)** | | **~$17-27/month** |

### Forwarder (Steps 1-6)

| Resource | SKU | Monthly Cost |
|----------|-----|--------------|
| Storage Account (Internal) | Standard LRS | ~$5/month |
| Event Hub | Standard (1 TU) | ~$20/month |
| Function App | Consumption | ~$5-20/month |
| Event Grid | Per event | ~$1/month |
| **Subtotal (Forwarder)** | | **~$31-46/month** |

### Total Monthly Cost

**Basic Setup (100 VMs)**: ~$48-73/month
**Enterprise Setup (1000+ VMs)**: ~$407-467/month (with Premium Function + auto-inflate)

---

## ✅ Validation Checkpoints

### After Step 0 (Prerequisites)

- [ ] Virtual Network exists and has at least one subnet
- [ ] Network Security Group is associated with VNet subnet
- [ ] Network Watcher is enabled for your region
- [ ] Storage Account (source) is created
- [ ] VNet Flow Logs configuration shows "Enabled" status
- [ ] Container `insights-logs-flowlogflowevent` exists in source storage
- [ ] PT1H.json files are being created
- [ ] PT1H.json files are being updated (check file size changes)

### After Steps 1-6 (Forwarder)

- [ ] Storage Account (internal) exists
- [ ] Event Hub Namespace and Event Hub exist
- [ ] Consumer Group exists
- [ ] Function App exists with Managed Identity enabled
- [ ] Event Grid System Topic monitors source storage
- [ ] Event Grid Subscription filters PT1H.json files
- [ ] Function App has "Storage Blob Data Reader" role on source storage
- [ ] Function code is deployed
- [ ] Function "VNetFlowLogsForwarder" appears in portal

### After Step 8 (End-to-End Testing)

- [ ] Upload test blob triggers Event Grid event
- [ ] Event appears in Event Hub metrics
- [ ] Function invocation count increases
- [ ] Function logs show successful processing
- [ ] Logs appear in New Relic with correct format
- [ ] No errors in Function App logs

---

## 🚨 Common Issues & Solutions

### Step 0 Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Container not created | Flow logs need time to start | Wait 5-10 minutes after enabling |
| PT1H.json not appearing | No network traffic | Deploy test VM or generate traffic |
| Flow logs not updating | NSG not associated | Check NSG is linked to subnet |
| "Insufficient permissions" | Missing IAM role | Need Contributor on subscription |

### Steps 1-6 Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Event Grid can't create | Wrong storage account | Use source storage (not internal) |
| Events not reaching Event Hub | Filters too restrictive | Check Subject filters |
| Function not triggering | Wrong connection string | Use Namespace connection string |
| Function can't read blobs | Missing RBAC | Assign Storage Blob Data Reader |
| Logs not in New Relic | Wrong license key | Check NR_LICENSE_KEY setting |

---

## 🎓 Learning Path

### For First-Time Setup

1. **Start with Prerequisites** (Step 0)
   - Learn about VNets, NSGs, Network Watcher
   - Understand flow log format and structure
   - See how data is written to storage

2. **Set Up Forwarder** (Steps 1-6)
   - Learn Event Grid event-driven patterns
   - Understand Event Hub as message broker
   - Practice with Managed Identities

3. **Test & Validate** (Steps 7-8)
   - Monitor metrics and logs
   - Troubleshoot issues
   - Verify data quality

### For Production Deployment

1. **Use ARM Template** (faster, repeatable)
   - See: `azuredeploy-vnetflowlogsforwarder.json`
   - Modify parameters for your environment
   - Deploy via CLI or Azure Portal

2. **Add Monitoring**
   - Set up Application Insights
   - Create alerts for failures
   - Monitor costs

3. **Scale & Optimize**
   - Consider Enterprise plan for high volume
   - Add private VNet for security
   - Implement delta extraction for efficiency

---

## 📚 Related Documentation

| Document | Purpose |
|----------|---------|
| [MANUAL_UI_SETUP_GUIDE.md](./MANUAL_UI_SETUP_GUIDE.md) | Detailed step-by-step UI instructions |
| [RESOURCE_LINKAGE_MAP.md](./RESOURCE_LINKAGE_MAP.md) | Visual reference for connections |
| [MVP_PLAN.md](./MVP_PLAN.md) | Simplified MVP approach |
| [README-vnetflowlogsforwarder.md](./README-vnetflowlogsforwarder.md) | ARM template documentation |
| [SPIKE_SUMMARY_VNetFlowLogs.md](./SPIKE_SUMMARY_VNetFlowLogs.md) | Spike findings and decisions |

---

## 🎯 Quick Start Paths

### Path 1: I Have Nothing Set Up Yet
**Time**: 2-3 hours
1. Follow **Step 0** (Prerequisites) in MANUAL_UI_SETUP_GUIDE.md
2. Follow **Steps 1-8** (Forwarder) in MANUAL_UI_SETUP_GUIDE.md
3. Verify in New Relic

### Path 2: I Have VNet & Flow Logs Already
**Time**: 1-2 hours
1. Skip Step 0
2. Follow **Steps 1-8** in MANUAL_UI_SETUP_GUIDE.md
3. Verify in New Relic

### Path 3: I Want Automated Deployment
**Time**: 30 minutes
1. Ensure VNet & Flow Logs exist (Step 0)
2. Deploy ARM template: `azuredeploy-vnetflowlogsforwarder.json`
3. Grant RBAC permissions (manual step)
4. Verify in New Relic

---

**Ready to get started?** → Open [MANUAL_UI_SETUP_GUIDE.md](./MANUAL_UI_SETUP_GUIDE.md)
