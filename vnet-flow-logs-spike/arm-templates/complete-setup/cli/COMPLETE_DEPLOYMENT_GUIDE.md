# Complete VNet Flow Logs Setup - Single ARM Template Deployment

This guide deploys **EVERYTHING from scratch** in one go - perfect for spikes and POCs.

## 🎯 What Gets Created

### Prerequisites (Automated)
- ✅ Virtual Network (VNet) with subnet
- ✅ Network Security Group (NSG)
- ✅ Network Watcher
- ✅ **VNet Flow Logs** configuration (new Azure recommendation, NSG flow logs are being retired)
- ✅ Source Storage Account (where Network Watcher writes PT1H.json files)

### Forwarder Infrastructure (Automated)
- ✅ Event Grid System Topic (monitors source storage)
- ✅ Event Grid Subscription (filters PT1H.json files)
- ✅ Event Hub Namespace + Event Hub
- ✅ Function App + Internal Storage Account
- ✅ **Automatic role assignment** (Function App → Source Storage)

### What You Still Need to Do (Manual)
- 📦 Deploy your LogForwarder code (2 minutes)
- ⏰ Wait for flow logs to generate (~10 minutes)

---

## 🚀 Quick Start (15-20 minutes total)

### Step 1: Deploy Infrastructure (10-15 minutes)

```bash
cd /Users/bpavan/repos/logint/nr/newrelic-azure-functions/vnet-flow-logs-spike/arm-templates/

# Deploy everything
./deploy-complete.sh bpavan-vnet-logs-arm canadacentral
```

**What happens:**
1. Creates resource group
2. Validates template
3. Shows what-if preview
4. Deploys all resources
5. Outputs all resource names

**Expected outputs:**
```
Virtual Network: bpavan-vnet
Network Security Group: bpavan-vnet-nsg
VNet Flow Logs: bpavan-vnet-flowlogs (targets VNet, not NSG)
Source Storage: bpavanXXXXXXXXXX (PT1H.json files)
Event Hub: bpavan-vnet-eventhub
Function App: bpavan-vnet-func-XXXXXXXXXX
```

---

### Step 2: Deploy Function Code (2 minutes)

```bash
cd /Users/bpavan/repos/logint/nr/newrelic-azure-functions

# Package code
npm run package:logforwarder

# Get function app name
FUNCTION_APP_NAME=$(az functionapp list \
  --resource-group bpavan-vnet-logs-arm \
  --query "[0].name" \
  --output tsv)

echo "Deploying to: $FUNCTION_APP_NAME"

# Deploy
az functionapp deployment source config-zip \
  --resource-group bpavan-vnet-logs-arm \
  --name $FUNCTION_APP_NAME \
  --src LogForwarder.zip

# Restart
az functionapp restart \
  --resource-group bpavan-vnet-logs-arm \
  --name $FUNCTION_APP_NAME
```

---

### Step 3: Wait for Flow Logs (5-10 minutes) ⏰

Network Watcher needs time to:
1. Start monitoring the NSG
2. Collect network traffic
3. Generate the first PT1H.json file

**During this time:**
- Check Azure Portal → Storage Account → Containers
- Look for `insights-logs-flowlogflowevent` container
- First PT1H.json file will appear in ~5-10 minutes

**To generate traffic faster (optional):**
```bash
# Create a test VM in the VNet (this will generate traffic)
# Or just wait - flow logs will generate even without VMs
```

---

### Step 4: Monitor and Verify (2 minutes)

#### Monitor Function Logs:

```bash
az webapp log tail \
  --resource-group bpavan-vnet-logs-arm \
  --name $FUNCTION_APP_NAME
```

**Expected logs (once PT1H.json appears):**
```
==== VNetFlowLogsForwarder Triggered ====
Received 1 Event Grid event(s)
Event Type: Microsoft.Storage.BlobCreated
Blob URL: .../PT1H.json
✓ VALIDATED: This is a VNet Flow Log file
Got response:202
Logs payload successfully sent to New Relic.
```

#### Check New Relic:

```sql
SELECT * FROM Log
WHERE logtype = 'azure.vnet.flowlog.validation'
SINCE 15 minutes ago
ORDER BY timestamp DESC
```

---

## 📋 What's Different from the Original ARM Template?

| Feature | Original Template | Complete Template |
|---------|------------------|-------------------|
| **VNet** | ❌ Not included (prerequisite) | ✅ Automated |
| **NSG** | ❌ Not included (prerequisite) | ✅ Automated |
| **Network Watcher** | ❌ Not included (prerequisite) | ✅ Automated |
| **Flow Logs Config** | ❌ Not included (prerequisite) | ✅ Automated |
| **Source Storage** | ❌ Must exist beforehand | ✅ Created automatically |
| **Event Grid** | ✅ Included | ✅ Included |
| **Event Hub** | ✅ Included | ✅ Included |
| **Function App** | ✅ Included | ✅ Included |
| **Role Assignment** | ⚠️  Manual step required | ✅ Automatic |
| **Total Deployment Time** | 5-10 min + manual prerequisites | 10-15 min (everything) |

---

## 🎛️ Configuration Options

Edit `azuredeploy-vnetflowlogs-complete.parameters.json`:

```json
{
  "newRelicLicenseKey": {
    "value": "your-license-key"           // Your NR license key
  },
  "vnetName": {
    "value": "bpavan-vnet"                 // VNet name
  },
  "vnetAddressPrefix": {
    "value": "10.1.0.0/16"                 // VNet CIDR
  },
  "subnetAddressPrefix": {
    "value": "10.1.0.0/24"                 // Subnet CIDR
  },
  "location": {
    "value": "canadacentral"               // Azure region
  },
  "flowLogsRetentionDays": {
    "value": 7                             // Retention (0 = forever)
  }
}
```

---

## 🔍 Verification Checklist

### Immediate (Right after deployment):

- [ ] Resource group created
- [ ] VNet and subnet created
- [ ] NSG created and associated with subnet
- [ ] Source storage account exists
- [ ] Event Grid System Topic created
- [ ] Event Hub created
- [ ] Function App running
- [ ] Flow Logs configuration enabled

**Check:**
```bash
az group show --name bpavan-vnet-logs-arm
az network vnet list --resource-group bpavan-vnet-logs-arm --output table
az network nsg list --resource-group bpavan-vnet-logs-arm --output table
az functionapp list --resource-group bpavan-vnet-logs-arm --output table
```

### After 10 minutes (Flow logs should be generating):

- [ ] PT1H.json files appearing in source storage
- [ ] Event Grid receiving events
- [ ] Function triggering on events
- [ ] Logs appearing in New Relic

**Check source storage:**
```bash
SOURCE_STORAGE=$(az storage account list \
  --resource-group bpavan-vnet-logs-arm \
  --query "[?starts_with(name, 'vnetflowsrc')].name" \
  --output tsv)

az storage container list \
  --account-name $SOURCE_STORAGE \
  --query "[?name=='insights-logs-flowlogflowevent']" \
  --output table
```

---

## 🗑️ Cleanup

Delete everything in one command:

```bash
az group delete --name bpavan-vnet-logs-arm --yes --no-wait
```

This removes:
- VNet, NSG, subnet
- Network Watcher flow logs configuration
- Both storage accounts (source + internal)
- Event Grid, Event Hub
- Function App
- Everything else

---

## 💡 When to Use This Template

| Scenario | Use This? |
|----------|-----------|
| **Spike/POC** | ✅ YES - Perfect! |
| **Learning/Demo** | ✅ YES - Everything in one go |
| **Quick test environment** | ✅ YES - Fast setup |
| **Production (existing VNet)** | ❌ NO - Use original template |
| **Production (new VNet)** | ⚠️  MAYBE - Review networking first |

---

## ⚠️ Important Notes

### VNet Flow Logs (Updated 2025)
- **This template uses VNet Flow Logs, not NSG Flow Logs**
- Azure blocked creation of new NSG flow logs starting June 30, 2025
- NSG flow logs will be retired September 30, 2027
- VNet Flow Logs are the recommended approach going forward
- [Migration Guide](https://learn.microsoft.com/en-us/azure/network-watcher/nsg-flow-logs-migrate)

### Event Hub Consumer Group
- **Basic tier Event Hub uses `$Default` consumer group**
- Custom consumer groups are only available in Standard tier
- This is a limitation of the Basic tier but works fine for the forwarder

### Network Watcher Regional Limitation
- Network Watcher is **one per region per subscription**
- If you already have Network Watcher in the region, the template will use it
- This is normal and expected

### Flow Logs Delay
- **First logs appear:** 5-10 minutes after deployment
- **Regular updates:** Every ~60 seconds
- **Be patient!** This is normal Azure behavior

### NSG Traffic
- The NSG allows all traffic (for demo purposes)
- In production, configure proper security rules
- Flow logs work regardless of NSG rules

---

## 🆚 Comparison: Complete vs Original Template

### Use Complete Template When:
- ✅ Starting from scratch
- ✅ Running a spike/POC
- ✅ Need everything automated
- ✅ Don't have existing VNet/Flow Logs

### Use Original Template When:
- ✅ You already have VNet and Flow Logs
- ✅ Flow logs are in a different subscription
- ✅ You want to control VNet separately
- ✅ Production deployment with existing infrastructure

---

## 📊 Resource Costs

**Monthly cost estimate (complete setup):**

| Resource | Cost/Month (USD) |
|----------|------------------|
| VNet + Subnet | $0 (free) |
| NSG | $0 (free) |
| Network Watcher Flow Logs | ~$5-10 (processing + storage) |
| Source Storage Account | ~$2-5 (blob storage) |
| Event Hub | ~$20 (Standard tier) |
| Event Grid | ~$1 (events) |
| Function App | ~$20 (consumption) |
| Internal Storage | ~$2 (minimal) |
| **Total** | **~$50-58/month** |

---

## 🎓 Learning Tips

After deployment, explore:

1. **Source Storage** → See PT1H.json file structure
2. **Event Grid Metrics** → Watch events flowing
3. **Event Hub Metrics** → See message throughput
4. **Function App Logs** → See processing in real-time
5. **New Relic** → Query the logs

---

**Ready to deploy?** Run `./deploy-complete.sh bpavan-vnet-logs-arm canadacentral`! 🚀