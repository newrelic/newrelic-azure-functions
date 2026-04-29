# Generate VNet Flow Logs Traffic

Now that your infrastructure is deployed, you need to generate network traffic to test the pipeline.

## Quick Check: Are Logs Already Generating?

VNet Flow Logs capture ALL traffic in the VNet, including Azure infrastructure traffic. Let's check if logs are already being generated:

```bash
# Get the source storage account name
SOURCE_STORAGE=$(az storage account list \
  --resource-group bpavan-vnet-logs-arm \
  --query "[?starts_with(name, 'bpavan')].name | [0]" \
  --output tsv)

echo "Source Storage Account: $SOURCE_STORAGE"

# Check if flow logs container exists
az storage container list \
  --account-name $SOURCE_STORAGE \
  --auth-mode login \
  --query "[?name=='insights-logs-flowlogflowevent']" \
  --output table

# List blobs in the container (if it exists)
az storage blob list \
  --account-name $SOURCE_STORAGE \
  --container-name insights-logs-flowlogflowevent \
  --auth-mode login \
  --query "[].{Name:name, Size:properties.contentLength, Modified:properties.lastModified}" \
  --output table | head -20
```

**Expected Result:**
- Container `insights-logs-flowlogflowevent` should exist
- If PT1H.json files are present, logs are already generating!
- Wait 5-10 minutes for first logs if container is empty

---

## Option 1: Deploy Test VM (Recommended for Testing) 🚀

Deploy a simple Linux VM in the VNet to generate network traffic:

```bash
# Variables
RESOURCE_GROUP="bpavan-vnet-logs-arm"
VNET_NAME="bpavan-vnet"
SUBNET_NAME="default"
VM_NAME="test-vm-flowlogs"
VM_SIZE="Standard_B1s"  # Cheapest VM (~$10/month)
LOCATION="canadacentral"

# Create VM (uses SSH key, no password needed)
az vm create \
  --resource-group $RESOURCE_GROUP \
  --name $VM_NAME \
  --image Ubuntu2204 \
  --size $VM_SIZE \
  --vnet-name $VNET_NAME \
  --subnet $SUBNET_NAME \
  --location $LOCATION \
  --generate-ssh-keys \
  --public-ip-sku Standard \
  --nsg "" \
  --output table

echo "VM created! It will generate network traffic automatically."
```

**What generates traffic:**
- VM boot process (DNS, DHCP, Azure metadata service)
- Background OS updates
- Azure agent communication
- SSH connections (if you connect)

**Generate more traffic (optional):**
```bash
# SSH into the VM
VM_IP=$(az vm list-ip-addresses \
  --resource-group $RESOURCE_GROUP \
  --name $VM_NAME \
  --query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" \
  --output tsv)

ssh azureuser@$VM_IP

# Inside the VM, generate traffic:
# DNS lookups
nslookup google.com
nslookup microsoft.com
nslookup newrelic.com

# HTTP requests (generates outbound traffic)
curl -I https://www.google.com
curl -I https://www.microsoft.com
curl -I https://api.newrelic.com

# Ping (generates ICMP traffic)
ping -c 10 8.8.8.8

# Exit SSH
exit
```

---

## Option 2: Use Azure Cloud Shell (Quick & Free) ☁️

If you don't want to deploy a VM, use Azure Cloud Shell to generate traffic:

```bash
# Get VNet ID
VNET_ID=$(az network vnet show \
  --resource-group bpavan-vnet-logs-arm \
  --name bpavan-vnet \
  --query id \
  --output tsv)

# Note: Cloud Shell isn't IN your VNet, so this won't generate VNet Flow Logs
# You MUST deploy a VM or use existing resources in the VNet
```

**Note:** Cloud Shell doesn't work for this purpose because it's not inside your VNet.

---

## Option 3: Deploy Azure Container Instance (Quick, Pay-per-use) 🐳

Deploy a container that runs in the VNet:

```bash
RESOURCE_GROUP="bpavan-vnet-logs-arm"
VNET_NAME="bpavan-vnet"
SUBNET_NAME="default"
CONTAINER_NAME="test-aci-flowlogs"

# Create a subnet for ACI (if not already created)
az network vnet subnet create \
  --resource-group $RESOURCE_GROUP \
  --vnet-name $VNET_NAME \
  --name aci-subnet \
  --address-prefixes 10.1.1.0/24 \
  --delegations Microsoft.ContainerInstance/containerGroups \
  --output table || true

# Deploy container that generates traffic
az container create \
  --resource-group $RESOURCE_GROUP \
  --name $CONTAINER_NAME \
  --image nginx:alpine \
  --vnet $VNET_NAME \
  --subnet aci-subnet \
  --cpu 1 \
  --memory 0.5 \
  --output table

echo "Container deployed! It generates traffic automatically."
```

---

## Monitor Flow Logs Generation (5-10 minutes) ⏰

After deploying a VM or container, wait 5-10 minutes and monitor:

### Check Storage Account for PT1H.json Files

```bash
SOURCE_STORAGE=$(az storage account list \
  --resource-group bpavan-vnet-logs-arm \
  --query "[?starts_with(name, 'bpavan')].name | [0]" \
  --output tsv)

# Watch for new blobs (run this multiple times)
watch -n 30 "az storage blob list \
  --account-name $SOURCE_STORAGE \
  --container-name insights-logs-flowlogflowevent \
  --auth-mode login \
  --query \"[].{Name:name, Size:properties.contentLength}\" \
  --output table | head -20"
```

### Check Event Grid Metrics

```bash
# Get Event Grid topic name
EVENT_GRID_TOPIC=$(az eventgrid system-topic list \
  --resource-group bpavan-vnet-logs-arm \
  --query "[0].name" \
  --output tsv)

echo "Event Grid Topic: $EVENT_GRID_TOPIC"

# Check metrics in Azure Portal:
# Portal → Event Grid System Topics → $EVENT_GRID_TOPIC → Metrics
```

### Monitor Function App Logs (Real-time)

```bash
FUNCTION_APP_NAME=$(az functionapp list \
  --resource-group bpavan-vnet-logs-arm \
  --query "[0].name" \
  --output tsv)

echo "Monitoring Function App: $FUNCTION_APP_NAME"
echo "Waiting for PT1H.json events..."
echo ""

# Live tail logs
az webapp log tail \
  --resource-group bpavan-vnet-logs-arm \
  --name $FUNCTION_APP_NAME
```

**Expected logs when working:**
```
==== VNetFlowLogsForwarder Triggered ====
Received 1 Event Grid event(s)
Event Type: Microsoft.Storage.BlobCreated
Blob URL: https://bpavanXXXXXX.blob.core.windows.net/.../PT1H.json
✓ VALIDATED: This is a VNet Flow Log file
Downloaded blob size: 12345 bytes
Processing flow log records...
Got response:202
Logs payload successfully sent to New Relic.
```

---

## Verify in New Relic (After logs are sent) 🔍

Once you see "successfully sent to New Relic" in function logs:

### Query VNet Flow Logs in New Relic

```sql
-- All VNet flow logs
SELECT * FROM Log
WHERE logtype = 'azure.vnet.flowlog'
SINCE 30 minutes ago
LIMIT 100

-- Summary by source IP
SELECT count(*) as FlowCount,
       source_ip,
       destination_ip,
       destination_port
FROM Log
WHERE logtype = 'azure.vnet.flowlog'
SINCE 30 minutes ago
GROUP BY source_ip, destination_ip, destination_port
ORDER BY FlowCount DESC

-- Traffic by protocol
SELECT count(*) as FlowCount, protocol
FROM Log
WHERE logtype = 'azure.vnet.flowlog'
SINCE 30 minutes ago
FACET protocol
```

---

## Cleanup (When done testing)

### Delete Test VM

```bash
az vm delete \
  --resource-group bpavan-vnet-logs-arm \
  --name test-vm-flowlogs \
  --yes \
  --no-wait

# Delete VM's disk and NIC
az disk delete \
  --resource-group bpavan-vnet-logs-arm \
  --name test-vm-flowlogsOSDisk \
  --yes \
  --no-wait

az network nic delete \
  --resource-group bpavan-vnet-logs-arm \
  --name test-vm-flowlogsVMNic \
  --no-wait

az network public-ip delete \
  --resource-group bpavan-vnet-logs-arm \
  --name test-vm-flowlogsPublicIP \
  --no-wait
```

### Delete Container Instance

```bash
az container delete \
  --resource-group bpavan-vnet-logs-arm \
  --name test-aci-flowlogs \
  --yes
```

---

## Troubleshooting

### No PT1H.json files after 10 minutes?

1. **Check VNet Flow Logs status:**
   ```bash
   az network watcher flow-log list \
     --location canadacentral \
     --query "[?contains(name, 'bpavan')]" \
     --output table
   ```

2. **Verify Flow Logs are enabled:**
   ```bash
   az network watcher flow-log show \
     --location canadacentral \
     --name bpavan-vnet-flowlogs \
     --query "{Enabled:enabled, Target:targetResourceId, Storage:storageId}"
   ```

3. **Check storage account permissions:**
   - Network Watcher needs write access to storage account
   - Should be automatically configured by ARM template

### Function not triggering?

1. **Check Event Grid subscription:**
   ```bash
   az eventgrid system-topic event-subscription show \
     --name $(az eventgrid system-topic event-subscription list \
       --resource-group bpavan-vnet-logs-arm \
       --system-topic-name $(az eventgrid system-topic list \
         --resource-group bpavan-vnet-logs-arm \
         --query "[0].name" -o tsv) \
       --query "[0].name" -o tsv) \
     --resource-group bpavan-vnet-logs-arm \
     --system-topic-name $(az eventgrid system-topic list \
       --resource-group bpavan-vnet-logs-arm \
       --query "[0].name" -o tsv)
   ```

2. **Verify function code is deployed:**
   ```bash
   az functionapp show \
     --resource-group bpavan-vnet-logs-arm \
     --name $FUNCTION_APP_NAME \
     --query "state"
   ```

---

## Summary

**Recommended Approach for Testing:**
1. ✅ Deploy a small test VM (Option 1) - generates immediate, consistent traffic
2. ⏰ Wait 5-10 minutes for first PT1H.json file
3. 👀 Monitor function logs with `az webapp log tail`
4. 🔍 Verify logs in New Relic
5. 🗑️ Delete test VM when done

**Cost:** Test VM costs ~$0.01/hour, so testing for 1 hour costs about 1 cent.
