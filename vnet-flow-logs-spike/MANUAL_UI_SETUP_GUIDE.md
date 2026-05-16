# Manual UI Setup Guide: VNet Flow Logs Forwarder

## Overview

This guide walks you through creating the VNet Flow Logs forwarder **manually using Azure Portal UI**. Follow these steps in order.

**Goal**: Set up Event Grid → Event Hub → Azure Function → New Relic pipeline

**Time Required**:
- **With existing VNet & Flow Logs**: 1-2 hours
- **Starting from scratch (includes Step 0)**: 2-3 hours

---

## Prerequisites

Before you start, ensure you have:

- ✅ Azure subscription with Owner or Contributor access
- ✅ New Relic License Key
- ✅ Resource Group created (or create a new one)

**If you don't have VNet Flow Logs set up yet**, follow **Step 0** below to create:
- Virtual Network (VNet)
- Network Watcher
- Storage Account for flow logs
- VNet Flow Logs configuration

**If you already have VNet Flow Logs running**, skip to **Step 1**.

---

## Step 0: Set Up VNet and Network Watcher (Prerequisites)

**⚠️ Skip this section if you already have Network Watcher writing VNet Flow Logs to a Storage Account.**

This section sets up the infrastructure needed to generate VNet Flow Logs.

**Time Required**: 30-45 minutes

### 0A: Create Virtual Network (VNet)

**Purpose**: Create a VNet where your VMs/resources will run (this generates network traffic)

1. **Navigate to Virtual Networks**
   - Azure Portal → Search "Virtual networks" → Click "Create"

2. **Basics Tab**
   ```
   Resource group: [Select or create, e.g., "vnetflowlogs-demo-rg"]
   Name: demo-vnet
   Region: East US (or your preferred region)
   ```

3. **IP Addresses Tab**
   ```
   IPv4 address space: 10.0.0.0/16 (default is fine)

   Click "+ Add subnet"
   Subnet name: default
   Subnet address range: 10.0.0.0/24
   ```

4. **Security Tab**
   ```
   BastionHost: Disabled (for demo)
   Firewall: Disabled (for demo)
   DDoS Protection: Disabled (for demo)
   ```

5. **Review + Create**
   - Click "Review + create"
   - Click "Create"
   - Wait 10-20 seconds

6. **Note Down**
   ```
   VNet Name: _________________ (e.g., demo-vnet)
   VNet Resource ID: _________________ (copy from Properties tab)
   ```

### 0B: Create Network Security Group (NSG)

**Purpose**: NSG is required for VNet Flow Logs (even if rules allow all traffic)

1. **Navigate to Network Security Groups**
   - Azure Portal → Search "Network security groups" → Click "Create"

2. **Basic Settings**
   ```
   Resource group: vnetflowlogs-demo-rg (same as VNet)
   Name: demo-nsg
   Region: East US (same as VNet)
   ```

3. **Review + Create**
   - Click "Review + create"
   - Click "Create"
   - Wait 10-20 seconds

4. **Associate NSG with VNet Subnet**
   - After NSG is created, click "Go to resource"
   - Click "Subnets" in left menu
   - Click "+ Associate"
   ```
   Virtual network: demo-vnet
   Subnet: default
   ```
   - Click "OK"

5. **Note Down**
   ```
   NSG Name: _________________ (e.g., demo-nsg)
   NSG Resource ID: _________________ (copy from Properties tab)
   ```

### 0C: Enable Network Watcher

**Purpose**: Network Watcher captures and exports network telemetry

**Note**: Network Watcher is automatically enabled in most regions. Check first before creating.

1. **Check if Network Watcher Exists**
   - Azure Portal → Search "Network Watcher"
   - Click "Network Watcher" (should appear in search)
   - Click "Overview" in left menu
   - Check if your region (e.g., "East US") is listed

2. **If Network Watcher Does NOT Exist for Your Region**
   - Click "+ Add" at the top
   ```
   Subscription: [Your subscription]
   Region: East US (same as your VNet)
   ```
   - Click "Add"
   - Wait 10-20 seconds

3. **Verify Network Watcher is Running**
   - Network Watcher → Overview
   - Your region should show:
     ```
     Region: East US
     Status: Enabled
     Resource group: NetworkWatcherRG (auto-created)
     ```

### 0D: Create Storage Account for Flow Logs

**Purpose**: Network Watcher writes VNet Flow Logs to this storage account

1. **Navigate to Storage Accounts**
   - Azure Portal → Search "Storage accounts" → Click "Create"

2. **Basic Settings**
   ```
   Resource group: vnetflowlogs-demo-rg (same as VNet)
   Storage account name: vnetflowlogssource[uniqueid]
                        (e.g., vnetflowlogssource12345)
                        (Must be globally unique, lowercase, no hyphens)
   Region: East US (same as VNet)
   Performance: Standard
   Redundancy: Locally-redundant storage (LRS)
   ```

3. **Advanced Settings**
   ```
   Security:
   - Require secure transfer (HTTPS): ✅ Enabled
   - Enable blob public access: ❌ Disabled
   - Enable storage account key access: ✅ Enabled

   Hierarchical namespace: ❌ Disabled
   ```

4. **Networking**
   ```
   Network connectivity: Public endpoint (all networks)
   ```

5. **Data Protection**
   ```
   Keep defaults (soft delete enabled is fine)
   ```

6. **Review + Create**
   - Click "Review + create"
   - Click "Create"
   - Wait 1-2 minutes

7. **Note Down**
   ```
   Storage Account Name: _________________ (you'll need this in Step 1 onwards)
   Storage Account Resource Group: _________________
   ```

### 0E: Enable VNet Flow Logs

**Purpose**: Configure Network Watcher to capture network flows and write to storage

1. **Navigate to Network Watcher**
   - Azure Portal → Search "Network Watcher"
   - Click "Network Watcher"

2. **Click "Flow logs"** in left menu (under Logs section)

3. **Click "+ Create"** at the top

4. **Select Resource Tab**
   ```
   Resource type: Network security group
   Subscription: [Your subscription]

   Click the checkbox next to your NSG:
   ✅ demo-nsg

   Click "Continue: Configuration >"
   ```

5. **Configuration Tab**
   ```
   Flow logs version: Version 2

   Storage Account:
   - Click "Select storage account"
   - Select: vnetflowlogssource12345 (the one you created in Step 0D)
   - Click "Save"

   Retention (days): 7 (or 0 for no retention limit)

   Traffic Analytics:
   ❌ Disable Traffic Analytics (for now)
   (We're processing raw logs, not using Traffic Analytics)
   ```

6. **Review + Create**
   - Click "Review + create"
   - Click "Create"
   - Wait 30-60 seconds

7. **Verify Flow Logs are Enabled**
   - Network Watcher → Flow logs
   - You should see:
     ```
     Name: demo-nsg-<region>-flowlog
     Target resource: demo-nsg
     Status: Enabled
     Storage account: vnetflowlogssource12345
     ```

### 0F: Generate Test Traffic (Optional but Recommended)

**Purpose**: Ensure flow logs are being written (easier to validate the forwarder)

**Option 1: Create a Test VM** (generates traffic automatically)

1. **Navigate to Virtual Machines**
   - Azure Portal → Search "Virtual machines" → Click "Create" → "Azure virtual machine"

2. **Basic Settings**
   ```
   Resource group: vnetflowlogs-demo-rg
   Virtual machine name: test-vm
   Region: East US (same as VNet)
   Image: Ubuntu Server 22.04 LTS
   Size: Standard_B1s (cheapest option, ~$10/month)

   Authentication:
   - Authentication type: Password
   - Username: azureuser
   - Password: [Create a strong password]
   ```

3. **Networking Tab**
   ```
   Virtual network: demo-vnet
   Subnet: default
   Public IP: Create new
   NIC network security group: Basic
   Select inbound ports: SSH (22)
   ```

4. **Review + Create**
   - Click "Review + create"
   - Click "Create"
   - Wait 2-3 minutes

5. **VM will generate traffic automatically** (DNS lookups, Azure management traffic, etc.)

**Option 2: Generate Traffic Manually** (if you don't want to create a VM)

```bash
# From your local machine or Azure Cloud Shell
# Replace with your VNet's public IPs if you have resources deployed

# Generate some outbound traffic
curl https://www.example.com
curl https://www.google.com
curl https://www.microsoft.com
```

### 0G: Verify Flow Logs are Being Written

**Purpose**: Confirm that PT1H.json files are being created before setting up the forwarder

1. **Navigate to Your Source Storage Account**
   - Azure Portal → Storage accounts → Click "vnetflowlogssource12345"

2. **Click "Storage browser"** in left menu

3. **Navigate to Containers**
   - Click "Blob containers"
   - You should see a container named: `insights-logs-flowlogflowevent`
   - Click on it

4. **Navigate to Flow Log Files**
   ```
   Path structure (expand folders):
   insights-logs-flowlogflowevent/
     resourceId=/
       SUBSCRIPTIONS/
         {subscription-id}/
           RESOURCEGROUPS/
             {resource-group-name}/
               PROVIDERS/
                 MICROSOFT.NETWORK/
                   NETWORKSECURITYGROUPS/
                     demo-nsg/
                       y={year}/
                         m={month}/
                           d={day}/
                             h={hour}/
                               m=00/
                                 macAddress={mac-address}/
                                   PT1H.json ← This file should exist!
   ```

5. **Download and Inspect PT1H.json** (optional)
   - Click on `PT1H.json`
   - Click "Download" button
   - Open the file - should contain JSON with flow records:
   ```json
   {
     "records": [{
       "time": "2026-04-23T10:00:00.000Z",
       "systemId": "...",
       "macAddress": "00-0D-3A-92-6A-7C",
       "category": "FlowLogFlowEvent",
       "flows": [...]
     }]
   }
   ```

6. **Wait for Updates**
   - Network Watcher updates PT1H.json files every **~60 seconds**
   - Download the file again after 1 minute - file size should have increased
   - This confirms flow logs are actively being written

**⚠️ Troubleshooting**:
- **Container doesn't exist**: Wait 5-10 minutes after enabling flow logs
- **PT1H.json doesn't exist**: Generate more traffic or wait longer
- **File is empty**: Check that NSG is associated with a subnet that has traffic
- **File not updating**: Verify flow logs status is "Enabled" in Network Watcher

---

### Summary: What You Created in Step 0

| Resource | Name | Purpose |
|----------|------|---------|
| **Virtual Network** | demo-vnet | Network where resources run |
| **Network Security Group** | demo-nsg | Required for flow logs |
| **Network Watcher** | (auto-created) | Captures network telemetry |
| **Storage Account** | vnetflowlogssource12345 | Stores PT1H.json flow log files |
| **Flow Logs Config** | demo-nsg-flowlog | Enables flow logging |
| **Virtual Machine** | test-vm (optional) | Generates traffic |

**You're now ready to proceed with Step 1!**

The storage account `vnetflowlogssource12345` is now:
- ✅ Receiving PT1H.json files from Network Watcher
- ✅ Files are being updated every ~60 seconds
- ✅ Ready to be monitored by Event Grid

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    YOUR EXISTING RESOURCES                   │
│                                                              │
│   Network Watcher → Storage Account (Source)                │
│                      └── PT1H.json files                     │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               │ detects blob updates
                               ↓
┌─────────────────────────────────────────────────────────────┐
│              RESOURCES YOU'LL CREATE (5 TOTAL)              │
│                                                              │
│   1. Event Grid System Topic                                │
│        ↓                                                     │
│   2. Event Grid Event Subscription (with filters)           │
│        ↓                                                     │
│   3. Event Hub Namespace + Event Hub                        │
│        ↓                                                     │
│   4. Storage Account (for Function state)                   │
│        ↓                                                     │
│   5. Function App (with Managed Identity)                   │
│        ↓                                                     │
│   New Relic Logs API                                        │
└─────────────────────────────────────────────────────────────┘
```

---

## Resource Creation Order

Create resources in this order to avoid dependency issues:

### Prerequisites (Step 0 - if not already set up):
0. ✅ Virtual Network (VNet)
0. ✅ Network Security Group (NSG)
0. ✅ Network Watcher
0. ✅ Storage Account (for Flow Logs - source)
0. ✅ VNet Flow Logs Configuration

### Forwarder Resources (Steps 1-6):
1. ✅ Storage Account (for Function internal state)
2. ✅ Event Hub Namespace + Event Hub
3. ✅ Function App
4. ✅ Event Grid System Topic
5. ✅ Event Grid Event Subscription
6. ✅ Grant Permissions (RBAC)

---

## Step 1: Create Storage Account (Internal)

**Purpose**: Store Function App state, logs, and Table Storage for cursor tracking

### UI Steps:

1. **Navigate to Storage Accounts**
   - Azure Portal → Search "Storage accounts" → Click "Create"

2. **Basic Settings**
   ```
   Resource group: [Select or create new, e.g., "vnetflowlogs-rg"]
   Storage account name: vnetflowlogsmvp[uniqueid]
                        (e.g., vnetflowlogsmvp12345)
   Region: [Same as your Function App will be, e.g., "East US"]
   Performance: Standard
   Redundancy: Locally-redundant storage (LRS)
   ```

3. **Advanced Settings**
   ```
   Security:
   - Require secure transfer (HTTPS): ✅ Enabled
   - Enable blob public access: ❌ Disabled

   Azure Files:
   - Keep defaults

   Data Lake Storage Gen2:
   - Keep defaults (disabled)
   ```

4. **Networking**
   ```
   Network connectivity: Public endpoint (all networks)

   (For MVP, use public access. Private VNet can be added later)
   ```

5. **Data Protection**
   ```
   Keep defaults (soft delete enabled is fine)
   ```

6. **Review + Create**
   - Click "Review + create"
   - Click "Create"
   - Wait 1-2 minutes for deployment

7. **Note Down**
   ```
   Storage Account Name: _________________ (you'll need this)
   ```

---

## Step 2: Create Event Hub Namespace + Event Hub

**Purpose**: Queue for Event Grid events (acts as bridge between Event Grid and Function)

### 2A: Create Event Hub Namespace

1. **Navigate to Event Hubs**
   - Azure Portal → Search "Event Hubs" → Click "Create"

2. **Basic Settings**
   ```
   Resource group: vnetflowlogs-rg (same as Step 1)
   Namespace name: vnetflowlogs-eventhub-ns
   Location: East US (same region as Storage Account)
   Pricing tier: Standard
   Throughput units: 1
   Enable Auto-Inflate: ❌ No (for MVP)
   ```

3. **Advanced Settings**
   ```
   Minimum TLS version: 1.2
   ```

4. **Networking**
   ```
   Connectivity method: Public endpoint (all networks)
   ```

5. **Review + Create**
   - Click "Review + create"
   - Click "Create"
   - Wait 2-3 minutes for deployment

### 2B: Create Event Hub (inside the Namespace)

1. **Navigate to Your Event Hub Namespace**
   - Azure Portal → Event Hubs → Click "vnetflowlogs-eventhub-ns"

2. **Create Event Hub**
   - Click "+ Event Hub" button at the top

   ```
   Name: vnetflowlogs-eventhub
   Partition Count: 4
   Message Retention: 1 day
   Capture: ❌ Off
   ```

3. **Click "Create"**
   - Wait 10-20 seconds

### 2C: Create Consumer Group

1. **Navigate to Your Event Hub**
   - Event Hub Namespace → Event Hubs → Click "vnetflowlogs-eventhub"

2. **Click "Consumer groups" in left menu**

3. **Click "+ Consumer group"**
   ```
   Name: vnetflowlogs-consumer
   ```

4. **Click "Create"**

### 2D: Get Connection String

1. **Navigate to Namespace Shared Access Policies**
   - Event Hub Namespace (not the Event Hub itself) → "Shared access policies" (left menu)

2. **Click "RootManageSharedAccessKey"**

3. **Copy "Connection string–primary key"**
   ```
   Connection String: _________________________________
   (Save this - you'll need it for Function App configuration)
   ```

---

## Step 3: Create Function App

**Purpose**: Process events from Event Hub and forward to New Relic

### UI Steps:

1. **Navigate to Function Apps**
   - Azure Portal → Search "Function App" → Click "Create"

2. **Basic Settings**
   ```
   Resource group: vnetflowlogs-rg (same as Steps 1-2)
   Function App name: vnetflowlogs-function

   Publish: Code
   Runtime stack: Node.js
   Version: 22 LTS
   Region: East US (same as other resources)

   Operating System: Linux
   Plan type: Consumption (Serverless)
   ```

3. **Storage**
   ```
   Storage account: vnetflowlogsmvp12345
   (Select the one you created in Step 1)
   ```

4. **Networking**
   ```
   Enable public access: ✅ On
   (For MVP - can add VNet later)
   ```

5. **Monitoring**
   ```
   Enable Application Insights: ✅ Yes
   (This helps with debugging)
   ```

6. **Deployment**
   ```
   Enable continuous deployment: ❌ No
   ```

7. **Review + Create**
   - Click "Review + create"
   - Click "Create"
   - Wait 2-3 minutes for deployment

### 3B: Enable Managed Identity

1. **Navigate to Your Function App**
   - Azure Portal → Function Apps → Click "vnetflowlogs-function"

2. **Click "Identity" in left menu**

3. **System assigned tab**
   ```
   Status: ✅ On
   ```

4. **Click "Save"** → Click "Yes" to confirm

5. **Note Down the Object (principal) ID**
   ```
   Object (principal) ID: _________________________________
   (You'll need this for granting permissions later)
   ```

### 3C: Configure Function App Settings

1. **Navigate to Configuration**
   - Function App → "Configuration" (left menu under Settings)

2. **Click "+ New application setting"** for each of these:

   | Name | Value | Notes |
   |------|-------|-------|
   | `EVENTHUB_NAME` | `vnetflowlogs-eventhub` | From Step 2B |
   | `EVENTHUB_CONSUMER_CONNECTION` | `Endpoint=sb://...` | Connection string from Step 2D |
   | `EVENTHUB_CONSUMER_GROUP` | `vnetflowlogs-consumer` | From Step 2C |
   | `NR_LICENSE_KEY` | `your-new-relic-license-key` | Your actual NR key |
   | `NR_ENDPOINT` | `https://log-api.newrelic.com/log/v1` | Use EU endpoint if needed |
   | `VNETFLOWLOGS_FORWARDER_ENABLED` | `true` | Enable the forwarder |
   | `SOURCE_STORAGE_ACCOUNT_NAME` | `yournetworkwatcherstorage` | Your existing storage with flow logs |
   | `VNETFLOWLOGS_STATE_TABLE_NAME` | `vnetflowlogsstate` | Table for cursor tracking |

3. **Click "Save"** at the top → Click "Continue" to confirm

4. **Wait for Function App to restart** (30-60 seconds)

---

## Step 4: Create Event Grid System Topic

**Purpose**: Capture events from your source Storage Account (where Network Watcher writes flow logs)

### UI Steps:

1. **Navigate to Event Grid System Topics**
   - Azure Portal → Search "Event Grid System Topics" → Click "Create"

2. **Basic Settings**
   ```
   Topic Type: Storage Accounts (filter the dropdown)

   Subscription: [Your subscription]
   Resource group: vnetflowlogs-rg

   Source Resource:
   - Click "Select a resource"
   - Navigate to your EXISTING storage account where Network Watcher writes flow logs
   - Select it (NOT the one you created in Step 1!)

   System topic name: vnetflowlogs-egtopic
   Region: [Auto-selected based on source storage]
   ```

3. **Review + Create**
   - Click "Review + create"
   - Click "Create"
   - Wait 30-60 seconds

**⚠️ Important**: The system topic is created on your **SOURCE storage account** (where Network Watcher writes), not the internal storage account from Step 1.

---

## Step 5: Create Event Grid Event Subscription

**Purpose**: Filter blob events and route them to Event Hub

### UI Steps:

1. **Navigate to Your System Topic**
   - Azure Portal → Event Grid System Topics → Click "vnetflowlogs-egtopic"

2. **Click "+ Event Subscription"** at the top

3. **Basic Settings**
   ```
   Name: vnetflowlogs-egsub
   Event Schema: Event Grid Schema

   Topic Details:
   - System Topic Name: vnetflowlogs-egtopic (pre-filled)
   ```

4. **Event Types**
   ```
   Filter to Event Types: ✅ Checked

   Event Types to Subscribe To:
   - ❌ Uncheck "Blob Created" (we'll add custom filter)
   - Click "Add event type"
   - Type: Microsoft.Storage.BlobCreated
   - ✅ Check it
   ```

5. **Endpoint Details**
   ```
   Endpoint Type: Event Hubs

   Select an endpoint:
   - Click "Select an endpoint"
   - Subscription: [Your subscription]
   - Event Hub namespace: vnetflowlogs-eventhub-ns
   - Event Hub: vnetflowlogs-eventhub
   - Click "Confirm Selection"
   ```

6. **Filters Tab** (IMPORTANT!)

   Click "Filters" tab at the top

   **Enable Subject Filtering**
   ```
   Enable subject filtering: ✅ Checked

   Subject Filters:
   - Subject Begins With: [Leave empty]
   - Subject Ends With: PT1H.json
   ```

   **Advanced Filters**
   ```
   Enable advanced filters: ✅ Checked

   Click "+ Add new filter"

   Filter 1:
   - Key: subject
   - Operator: String contains
   - Value: insights-logs-flowlogflowevent
   ```

   **Why these filters?**
   - `Subject Ends With: PT1H.json` → Only PT1H.json files (not other blobs)
   - `Subject Contains: insights-logs-flowlogflowevent` → Only VNet Flow Logs container

7. **Additional Features Tab**
   ```
   Retry policy:
   - Max number of attempts: 30
   - Event time to live (minutes): 1440 (24 hours)
   ```

8. **Click "Create"**
   - Wait 30-60 seconds

---

## Step 6: Grant Function App Access to Source Storage

**Purpose**: Allow Function App to read blobs from source storage using Managed Identity

### UI Steps:

1. **Navigate to Source Storage Account**
   - Azure Portal → Storage accounts
   - Click on your **source storage account** (where Network Watcher writes, NOT the internal one)

2. **Click "Access Control (IAM)"** in left menu

3. **Click "+ Add" → "Add role assignment"**

4. **Role Tab**
   ```
   Search for: Storage Blob Data Reader
   Select: Storage Blob Data Reader
   Click "Next"
   ```

5. **Members Tab**
   ```
   Assign access to: Managed identity

   Click "+ Select members"

   Managed identity:
   - Subscription: [Your subscription]
   - Managed identity: Function App
   - Select: vnetflowlogs-function

   Click "Select"
   Click "Next"
   ```

6. **Review + Assign**
   - Click "Review + assign"
   - Wait for role assignment to complete (10-30 seconds)

**Verification**:
- Go to "Access Control (IAM)" → "Role assignments" tab
- Filter by "Function App"
- You should see: `vnetflowlogs-function` with role `Storage Blob Data Reader`

---

## Step 7: Deploy Function Code

**Purpose**: Deploy the actual code that processes events

### Option A: Deploy from GitHub (Recommended for Testing)

1. **Navigate to Function App**
   - Azure Portal → Function Apps → Click "vnetflowlogs-function"

2. **Click "Deployment Center"** in left menu

3. **Settings**
   ```
   Source: External Git
   Repository: https://github.com/newrelic/newrelic-azure-functions
   Branch: main
   Repository Type: Public
   ```

4. **Click "Save"**

5. **Wait for deployment** (2-3 minutes)
   - Check "Logs" tab to see deployment progress

### Option B: Deploy Local Code (For Custom Development)

1. **Install Azure Functions Core Tools** (if not installed)
   ```bash
   npm install -g azure-functions-core-tools@4
   ```

2. **Login to Azure**
   ```bash
   az login
   ```

3. **Deploy from local repo**
   ```bash
   cd /Users/bpavan/repos/logint/nr/newrelic-azure-functions

   func azure functionapp publish vnetflowlogs-function
   ```

---

## Step 8: Verify the Setup

### 8A: Check Event Grid is Capturing Events

1. **Navigate to Event Grid System Topic**
   - Azure Portal → Event Grid System Topics → vnetflowlogs-egtopic

2. **Click "Metrics"** in left menu

3. **Add Metric**
   ```
   Metric: Publish Success Count
   Time range: Last 1 hour
   ```

4. **Expected**: Should show a line graph (even if 0, means it's working)

### 8B: Check Event Hub is Receiving Messages

1. **Navigate to Event Hub**
   - Azure Portal → Event Hubs → vnetflowlogs-eventhub-ns → vnetflowlogs-eventhub

2. **Click "Metrics"** in left menu

3. **Add Metric**
   ```
   Metric: Incoming Messages
   Time range: Last 1 hour
   ```

4. **Expected**: Should show incoming messages if VNet Flow Logs are being written

### 8C: Check Function App is Triggering

1. **Navigate to Function App**
   - Azure Portal → Function Apps → vnetflowlogs-function

2. **Click "Functions"** in left menu

3. **Expected**: Should see a function named "VNetFlowLogsForwarder"
   - If you don't see it, the code hasn't been deployed yet

4. **Click on the function name**

5. **Click "Monitor"** in left menu

6. **Expected**: Should see invocation logs (if events have been processed)

### 8D: View Live Logs

1. **Navigate to Function App**
   - Azure Portal → Function Apps → vnetflowlogs-function

2. **Click "Log stream"** in left menu (under Monitoring)

3. **Expected**: See real-time logs like:
   ```
   [VNetFlowLogs] Processing 1 Event Grid events
   [VNetFlowLogs] Processing blob: https://...PT1H.json
   [VNetFlowLogs] Downloaded 450 bytes
   [VNetFlowLogs] Parsed 1 flow log records
   [VNetFlowLogs] Successfully sent 1 logs to New Relic
   ```

---

## Step 9: Test End-to-End

### Test 1: Manual Blob Upload

1. **Navigate to Source Storage Account**
   - Azure Portal → Storage accounts → [Your source storage]

2. **Click "Storage browser"** in left menu

3. **Navigate to Blob containers**
   - Click "Blob containers"
   - Click "insights-logs-flowlogflowevent"

4. **Create Test File**
   - Create a file locally: `/tmp/test-PT1H.json`
   ```json
   {
     "records": [{
       "time": "2026-04-23T10:00:00.000Z",
       "systemId": "test-system",
       "macAddress": "00-0D-3A-92-6A-7C",
       "category": "FlowLogFlowEvent",
       "resourceId": "/subscriptions/test/resourceGroups/test-rg/providers/Microsoft.Network/networkSecurityGroups/test-nsg",
       "operationName": "NetworkSecurityGroupFlowEvents",
       "flows": [{
         "rule": "DefaultRule_AllowInternetOutBound",
         "flows": [{
           "flowState": "B",
           "flowTuples": ["1713870000,10.0.0.4,20.40.60.80,35678,443,T,O,A"]
         }]
       }]
     }]
   }
   ```

5. **Upload Test File**
   - Click "Upload" button
   - Browse to `/tmp/test-PT1H.json`
   - Virtual directory: `resourceId=/SUBSCRIPTIONS/test/RESOURCEGROUPS/test-rg/PROVIDERS/MICROSOFT.NETWORK/NETWORKSECURITYGROUPS/test-nsg/y=2026/m=04/d=23/h=10/m=00/macAddress=00-0D-3A-92-6A-7C/`
   - Filename: `PT1H.json`
   - Click "Upload"

6. **Wait 30-60 seconds**

7. **Check Function Logs**
   - Go to Function App → Log stream
   - Should see processing logs

### Test 2: Verify in New Relic

1. **Login to New Relic**
   - https://one.newrelic.com/

2. **Navigate to Logs**
   - Click "Logs" in left menu

3. **Query for VNet Flow Logs**
   ```
   logtype:"azure.vnet.flowlog"
   ```

4. **Expected**: See log entries with fields:
   - `sourceIP: 10.0.0.4`
   - `destIP: 20.40.60.80`
   - `sourcePort: 35678`
   - `destPort: 443`
   - `protocol: T`
   - `macAddress: 00-0D-3A-92-6A-7C`

---

## Configuration Summary

Here's what you created and how they're linked:

| Resource | Name | Purpose | Links To |
|----------|------|---------|----------|
| **Storage Account (Internal)** | `vnetflowlogsmvp12345` | Function state + Table Storage | Function App |
| **Event Hub Namespace** | `vnetflowlogs-eventhub-ns` | Messaging infrastructure | Event Grid + Function |
| **Event Hub** | `vnetflowlogs-eventhub` | Queue for blob events | Event Grid → Function |
| **Consumer Group** | `vnetflowlogs-consumer` | Function's event hub consumer | Function App |
| **Function App** | `vnetflowlogs-function` | Processes events | Event Hub → New Relic |
| **Managed Identity** | (on Function App) | Read source storage | Source Storage Account |
| **Event Grid System Topic** | `vnetflowlogs-egtopic` | Captures blob events | Source Storage Account |
| **Event Grid Subscription** | `vnetflowlogs-egsub` | Filters + routes events | System Topic → Event Hub |

---

## Data Flow Diagram

```
┌─────────────────────┐
│ Network Watcher     │
│ (Your existing)     │
└──────────┬──────────┘
           │ writes PT1H.json every 60 seconds
           ↓
┌─────────────────────┐
│ Source Storage      │◄──────────┐
│ (Your existing)     │           │
└──────────┬──────────┘           │
           │                      │ 5. Reads blob
           │ 1. BlobCreated event │    (Managed Identity)
           ↓                      │
┌─────────────────────┐           │
│ Event Grid          │           │
│ System Topic        │           │
│ (Step 4)            │           │
└──────────┬──────────┘           │
           │ 2. Filters events    │
           │    (PT1H.json only)  │
           ↓                      │
┌─────────────────────┐           │
│ Event Grid          │           │
│ Event Subscription  │           │
│ (Step 5)            │           │
└──────────┬──────────┘           │
           │ 3. Routes to         │
           ↓                      │
┌─────────────────────┐           │
│ Event Hub           │           │
│ (Step 2)            │           │
└──────────┬──────────┘           │
           │ 4. Triggers          │
           ↓                      │
┌─────────────────────┐           │
│ Function App        │───────────┘
│ (Step 3)            │
└──────────┬──────────┘
           │ 6. Sends logs
           ↓
┌─────────────────────┐
│ New Relic Logs API  │
└─────────────────────┘
```

---

## Troubleshooting

### Issue 1: Function Not Triggering

**Check**:
1. Function App → Configuration → Verify all app settings are correct
2. Event Hub → Metrics → Check "Incoming Messages" > 0
3. Function App → Functions → Verify "VNetFlowLogsForwarder" exists
4. Function App → Log stream → Check for errors

**Common Causes**:
- Wrong Event Hub connection string
- Function code not deployed
- `VNETFLOWLOGS_FORWARDER_ENABLED` not set to `true`

### Issue 2: Event Grid Not Routing Events

**Check**:
1. Event Grid System Topic → Metrics → Check "Publish Success Count"
2. Event Grid Subscription → Check filters are correct:
   - Subject ends with: `PT1H.json`
   - Subject contains: `insights-logs-flowlogflowevent`
3. Event Hub endpoint is correct

**Common Causes**:
- Filters too restrictive
- Wrong Event Hub endpoint
- Source storage account not writing blobs

### Issue 3: Function Can't Read Blobs

**Check**:
1. Function App → Identity → System assigned = On
2. Source Storage → Access Control (IAM) → Check "Storage Blob Data Reader" role assigned to Function App
3. Function App logs for "Authorization failed" errors

**Common Causes**:
- Managed Identity not enabled
- RBAC role not assigned
- Wrong source storage account name in config

### Issue 4: Logs Not Appearing in New Relic

**Check**:
1. Function App → Configuration → Verify `NR_LICENSE_KEY` is correct
2. Function App → Configuration → Verify `NR_ENDPOINT` is correct (US vs EU)
3. Function App logs for "401 Unauthorized" or "403 Forbidden"

**Common Causes**:
- Wrong license key
- Wrong endpoint (US vs EU)
- License key expired or invalid

---

## Cost Estimate (MVP)

| Resource | SKU | Estimated Monthly Cost |
|----------|-----|----------------------|
| Event Hub (Standard) | 1 throughput unit | ~$20 |
| Function App (Consumption) | Pay per execution | ~$5-20 |
| Storage Account (Internal) | Standard LRS | ~$5 |
| Event Grid | Per event | ~$1 |
| **Total** | | **~$31-46/month** |

---

## Next Steps

After validating the MVP:

1. **Add Delta Extraction** (eliminates duplication)
   - Implement Table Storage cursor tracking
   - Use block list API to download only new blocks

2. **Add Error Handling**
   - Retry logic
   - Dead letter queue
   - Alerting

3. **Add Private VNet** (optional, for security)
   - Create VNet + subnets
   - Add private endpoints
   - Configure private DNS zones

4. **Convert to ARM Template** (for repeatability)
   - Export resources to ARM template
   - Parameterize values
   - Add to CI/CD pipeline

---

## Summary Checklist

✅ Created Storage Account (internal)
✅ Created Event Hub Namespace + Event Hub + Consumer Group
✅ Created Function App with Managed Identity
✅ Configured Function App settings
✅ Created Event Grid System Topic on source storage
✅ Created Event Grid Event Subscription with filters
✅ Granted Function App read access to source storage
✅ Deployed function code
✅ Tested end-to-end
✅ Verified logs in New Relic

**Result**: VNet Flow Logs are now flowing to New Relic! 🎉