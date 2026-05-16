# Azure Portal Deployment Guide - Production-Style Workflow

## Deploy VNet Flow Logs Using Azure Portal UI

This guide shows you how to deploy the VNet Flow Logs ARM template using the **Azure Portal UI** - just like a production user would.

---

## Quick Start

### Option 1: Deploy via Portal (Recommended for Testing Production Flow)

1. **Navigate to Custom Template Deployment:**
   - Go to: https://portal.azure.com
   - Search for "Deploy a custom template"
   - Or direct link: https://portal.azure.com/#create/Microsoft.Template

2. **Load the Template:**
   - Click "Build your own template in the editor"
   - Copy the contents of `azuredeploy-vnetflowlogs-complete.json`
   - Paste into the editor
   - Click "Save"

3. **Fill the Form:**
   - Azure will generate a UI form from your template parameters
   - Fill in your values (see below)
   - Click "Review + create"

4. **Deploy:**
   - Review the resources to be created
   - Click "Create"
   - Wait 5-10 minutes

### Option 2: One-Click Deploy Button (Like Production Templates)

Create a "Deploy to Azure" button for your template (see below).

---

## Step-by-Step: Portal Deployment

### Step 1: Navigate to Custom Deployment

**Method A: Search Bar**
```
Azure Portal → Search "deploy a custom template" → Select "Deploy a custom template"
```

**Method B: Direct URL**
```
https://portal.azure.com/#create/Microsoft.Template
```

You'll see this screen:
```
┌──────────────────────────────────────────────┐
│ Custom deployment                            │
├──────────────────────────────────────────────┤
│                                              │
│  Select a template                           │
│  ○ Quickstart template                       │
│  ● Build your own template in the editor     │
│                                              │
│  [Build your own template in the editor]     │
│                                              │
└──────────────────────────────────────────────┘
```

---

### Step 2: Load Your Template

1. Click **"Build your own template in the editor"**

2. You'll see an editor with a sample template

3. **Delete all content** and paste your template:
   ```bash
   # Copy template content
   cat azuredeploy-vnetflowlogs-complete.json | pbcopy
   ```

4. Paste into the editor

5. Click **"Save"** button at the bottom

---

### Step 3: Fill the UI Form

Azure automatically generates a form from your template's parameters:

```
┌────────────────────────────────────────────────────────────┐
│ Custom deployment                                          │
├────────────────────────────────────────────────────────────┤
│                                                            │
│ Project details                                            │
│ ├─ Subscription:     [Visual Studio Enterprise ▼]         │
│ └─ Resource group:   [Create new]  [bpavan-vnet-portal]   │
│                                                            │
│ Instance details                                           │
│ ├─ Region:           [Canada Central ▼]                   │
│ └─ Location:         [leave blank]                        │
│                                                            │
│ New Relic Configuration                                    │
│ ├─ New Relic License Key: [d377ad18ef5078...65a1NRAL]    │
│ ├─ New Relic Endpoint:    [https://log-api.newrelic...▼] │
│ └─ Log Custom Attributes: [                          ]    │
│                                                            │
│ Network Configuration                                      │
│ ├─ Vnet Name:            [bpavan-vnet           ]         │
│ ├─ Vnet Address Prefix:  [10.1.0.0/16          ]         │
│ ├─ Subnet Name:          [default              ]         │
│ └─ Subnet Address Prefix:[10.1.0.0/24          ]         │
│                                                            │
│ Flow Logs Configuration                                    │
│ └─ Flow Logs Retention Days: [7]                         │
│                                                            │
│ Event Hub Configuration                                    │
│ ├─ Max Event Batch Size:  [20]                           │
│ ├─ Min Event Batch Size:  [5]                            │
│ └─ Max Wait Time:         [00:00:30]                     │
│                                                            │
│ [Review + create]  [Previous]  [Next]                     │
└────────────────────────────────────────────────────────────┘
```

---

### Step 4: Parameter Values Guide

Fill in the form with these values:

#### **Project Details**
- **Subscription:** Select your subscription
- **Resource group:** Create new → `bpavan-vnet-portal` (or any name)

#### **Instance Details**
- **Region:** `Canada Central` (must match your Network Watcher region)
- **Location:** Leave blank (will use resource group location)

#### **New Relic Configuration**
- **New Relic License Key:** `d377ad18ef50788f2341ed78fa6c853765a1NRAL`
- **New Relic Endpoint:** `https://log-api.newrelic.com/log/v1` (default)
- **Log Custom Attributes:** Leave blank (optional semicolon-separated tags)

#### **Network Configuration**
- **Vnet Name:** `bpavan-vnet`
- **Vnet Address Prefix:** `10.1.0.0/16`
- **Subnet Name:** `default`
- **Subnet Address Prefix:** `10.1.0.0/24`

#### **Flow Logs Configuration**
- **Flow Logs Retention Days:** `7` (0-365, 0 = forever)

#### **Event Hub Configuration**
- **Max Event Batch Size:** `20`
- **Min Event Batch Size:** `5`
- **Max Wait Time:** `00:00:30` (HH:MM:SS format)

---

### Step 5: Review and Deploy

1. Click **"Review + create"**

2. Azure validates the template:
   ```
   ✓ Validation passed
   ```

3. Review the deployment details:
   - Resource group location
   - Resources to be created (11 resources)
   - Estimated cost

4. Click **"Create"**

5. Monitor deployment progress:
   ```
   Deployment is in progress...

   ✓ Microsoft.Network/networkSecurityGroups
   ✓ Microsoft.Storage/storageAccounts (source)
   ✓ Microsoft.Storage/storageAccounts (internal)
   ✓ Microsoft.Web/serverfarms
   ✓ Microsoft.EventHub/namespaces
   ⏳ Microsoft.Network/virtualNetworks
   ⏳ Microsoft.EventHub/namespaces/eventhubs
   ```

6. Wait 5-10 minutes for completion

7. When done:
   ```
   ✓ Your deployment is complete

   Deployment name: Microsoft.Template-20260427123456
   Resource group: bpavan-vnet-portal
   ```

---

## Step 6: Verify Deployment

### Via Portal

1. Go to your resource group: `bpavan-vnet-portal`

2. Verify these resources exist:
   ```
   ✓ bpavan-vnet (Virtual network)
   ✓ bpavan-vnet-nsg (Network security group)
   ✓ bpavan7lk6nyehuzkgi (Storage account - source)
   ✓ bpavanint7lk6nyehuzkgi (Storage account - internal)
   ✓ bpavan-vnet-eventhub-ns-... (Event Hub Namespace)
   ✓ bpavan-vnet-eventhub (Event Hub)
   ✓ bpavan-vnet-func-... (Function App)
   ✓ bpavan-vnet-egtopic-... (Event Grid System Topic)
   ✓ bpavan-asp-... (App Service Plan)
   ✓ Application Insights
   ```

3. Check NetworkWatcherRG:
   ```
   Portal → Resource groups → NetworkWatcherRG

   ✓ NetworkWatcher_canadacentral
   ✓ bpavan-vnet-flowlogs (VNet Flow Log)
   ```

### Via CLI (Quick Check)

```bash
RESOURCE_GROUP="bpavan-vnet-portal"

# List all resources
az resource list --resource-group $RESOURCE_GROUP --output table

# Check Flow Logs
az network watcher flow-log show \
  --location canadacentral \
  --name bpavan-vnet-flowlogs
```

---

## Step 7: Deploy Function Code

**Important:** ARM template creates infrastructure but **doesn't deploy function code**!

### From Local Machine

```bash
# Navigate to repo root
cd /Users/bpavan/repos/logint/nr/newrelic-azure-functions

# Package function code
npm run package:logforwarder

# Get function app name from Portal or CLI
FUNCTION_APP=$(az functionapp list \
  --resource-group bpavan-vnet-portal \
  --query "[0].name" -o tsv)

echo "Function App: $FUNCTION_APP"

# Deploy code
az functionapp deployment source config-zip \
  --resource-group bpavan-vnet-portal \
  --name $FUNCTION_APP \
  --src LogForwarder.zip

# Restart function app
az functionapp restart \
  --resource-group bpavan-vnet-portal \
  --name $FUNCTION_APP
```

---

## Step 8: Test E2E Flow

### 1. Generate Traffic

Deploy a test VM to generate VNet traffic:

```bash
az vm create \
  --resource-group bpavan-vnet-portal \
  --name test-vm \
  --image Ubuntu2204 \
  --size Standard_B1s \
  --vnet-name bpavan-vnet \
  --subnet default \
  --location canadacentral \
  --generate-ssh-keys \
  --public-ip-sku Standard \
  --nsg ""
```

### 2. Monitor Function Logs (Portal)

1. Go to Function App: `bpavan-vnet-func-...`
2. Click "Log stream" (left menu under Monitoring)
3. Wait for connection
4. Watch for PT1H.json processing logs

Expected output (after 5-10 minutes):
```
==== VNetFlowLogsForwarder Triggered ====
Received 1 Event Grid event(s)
Event Type: Microsoft.Storage.BlobCreated
Blob URL: https://bpavan7lk6....blob.core.windows.net/.../PT1H.json
✓ VALIDATED: This is a VNet Flow Log file
Downloaded blob size: 33114 bytes
Processing flow log records...
Got response:202
Logs payload successfully sent to New Relic.
```

### 3. Verify in New Relic

Go to New Relic and run:
```sql
SELECT * FROM Log
WHERE logtype = 'azure.vnet.flowlog'
SINCE 30 minutes ago
LIMIT 100
```

---

## Create "Deploy to Azure" Button (Production Style)

### For GitHub Repository

Add this to your README:

```markdown
## Deploy VNet Flow Logs to Azure

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FYOUR_ORG%2FYOUR_REPO%2Fmain%2Fvnet-flow-logs-spike%2Farm-templates%2Fazuredeploy-vnetflowlogs-complete.json)
```

**Replace:**
- `YOUR_ORG` with your GitHub org/username
- `YOUR_REPO` with your repository name

**How it works:**
1. User clicks button
2. Opens Azure Portal with your template pre-loaded
3. User fills form
4. Deploys!

### For Testing (Local Template)

**Option 1: Upload to GitHub Gist**

1. Create a GitHub Gist with your template
2. Get the raw URL
3. URL encode it: https://www.urlencoder.org/
4. Use encoded URL in button:
   ```
   https://portal.azure.com/#create/Microsoft.Template/uri/ENCODED_URL
   ```

**Option 2: Use Azure Quickstart Templates Format**

1. Fork: https://github.com/Azure/azure-quickstart-templates
2. Add your template
3. Create PR or use your fork's URL

---

## Comparison: CLI vs Portal Deployment

| Aspect | CLI Deployment | Portal Deployment |
|--------|---------------|-------------------|
| **Method** | `az deployment group create` | UI form in browser |
| **Parameters** | Via parameters file or inline | Fill form fields |
| **Validation** | CLI output | Interactive validation |
| **Progress** | Terminal output | Visual progress bar |
| **Retry** | Re-run command | Click back, modify, re-submit |
| **Team Use** | Share script/parameters file | Share "Deploy to Azure" button |
| **Production Style** | Automation/IaC | ✅ **User self-service** |

---

## Troubleshooting Portal Deployment

### Issue: "Validation failed"

**Common causes:**
- Invalid CIDR notation (use 10.1.0.0/16, not 10.1.0.0/255)
- Location mismatch (must have Network Watcher in that region)
- Invalid parameter values

**Fix:** Review error messages, correct values, try again

### Issue: "Deployment failed"

**Check deployment output:**
1. Portal → Resource groups → Deployments
2. Click failed deployment
3. View error details:
   ```
   Code: ResourceDeploymentFailure
   Message: The resource write operation failed...
   Details: [Expand for details]
   ```

**Common errors:**
- Network Watcher quota exceeded → Use existing Network Watcher
- NSG flow logs blocked → Template already uses VNet flow logs ✓
- Role assignment scope mismatch → Fixed in template ✓

### Issue: Function not triggering

**Verify:**
1. Function code is deployed (Step 7 above)
2. PT1H.json files exist in storage
3. Event Grid subscription is active

**Check:**
```bash
# Monitor function logs in Portal
Portal → Function App → Log stream

# Or use CLI
az webapp log tail --name $FUNCTION_APP --resource-group bpavan-vnet-portal
```

---

## Production Deployment Workflow

### For Production Users

1. **Prepare:**
   - Determine network configuration (VNet CIDR)
   - Get New Relic license key
   - Choose Azure region

2. **Deploy Infrastructure:**
   - Click "Deploy to Azure" button (or use Portal)
   - Fill form with production values
   - Deploy

3. **Deploy Function Code:**
   - Download latest LogForwarder.zip from GitHub releases
   - Deploy via Portal or CLI:
     ```
     Portal → Function App → Deployment Center → Zip Deploy
     ```

4. **Verify:**
   - Check Flow Logs are generating
   - Monitor function logs
   - Verify logs in New Relic

5. **Generate Traffic:**
   - VNet automatically generates traffic from Azure infrastructure
   - Or deploy workloads to the VNet

6. **Monitor:**
   - Set up New Relic dashboards
   - Create alerts on flow log volume/errors

---

## Testing Production-Style Workflow

To fully test the production experience:

### 1. Start Fresh

```bash
# Delete existing spike resources
az group delete --name bpavan-vnet-logs-arm --yes --no-wait
```

### 2. Deploy via Portal (This Guide)

Follow Steps 1-5 above using the Portal UI.

### 3. Deploy Code (Manual Step)

Follow Step 7 above to deploy function code.

### 4. Test E2E

Follow Step 8 to generate traffic and verify logs in New Relic.

### 5. Document

- Screenshot the Portal deployment
- Note any UI/UX issues
- Validate parameter descriptions are clear
- Test "Deploy to Azure" button workflow

### 6. Compare Experience

**CLI Workflow (Automated):**
```bash
./deploy-complete.sh bpavan-vnet-logs-arm canadacentral
# Package and deploy code
# Test
```

**Portal Workflow (Production):**
```
1. Open Portal
2. Load template
3. Fill 11 parameter fields
4. Deploy (wait 5-10 min)
5. Deploy code manually
6. Test
```

**Which is better?**
- CLI: Faster for repeated testing, automation-ready
- Portal: More discoverable, self-service, production-style

---

## Enhancing Template for Portal Users

### Improve Parameter Descriptions

Make sure template parameters have clear descriptions:

```json
"vnetAddressPrefix": {
  "type": "string",
  "defaultValue": "10.1.0.0/16",
  "metadata": {
    "description": "Address space for the Virtual Network in CIDR notation (e.g., 10.1.0.0/16). This should not overlap with existing VNets."
  }
}
```

These descriptions appear as help text in the Portal form!

### Add Parameter Constraints

```json
"flowLogsRetentionDays": {
  "type": "int",
  "defaultValue": 7,
  "minValue": 0,
  "maxValue": 365,
  "metadata": {
    "description": "Number of days to retain flow logs in storage (0 = unlimited)"
  }
}
```

Portal validates these constraints automatically!

### Use allowedValues for Dropdowns

```json
"location": {
  "type": "string",
  "allowedValues": [
    "canadacentral",
    "canadaeast",
    "eastus",
    "eastus2",
    "westus2"
  ],
  "defaultValue": "canadacentral",
  "metadata": {
    "description": "Azure region (must have Network Watcher enabled)"
  }
}
```

Creates a dropdown in Portal!

---

## Summary

### Portal Deployment Steps

1. ✅ Portal → Deploy a custom template
2. ✅ Load `azuredeploy-vnetflowlogs-complete.json`
3. ✅ Fill UI form (11 parameters)
4. ✅ Deploy (5-10 minutes)
5. ✅ Deploy function code manually
6. ✅ Test E2E flow

### Benefits of Portal Testing

- ✅ Tests production user experience
- ✅ Validates parameter descriptions
- ✅ UI/UX feedback
- ✅ Self-service workflow validation
- ✅ No CLI knowledge required

### Next Steps for Production

1. Host template in public GitHub repo
2. Add "Deploy to Azure" button to README
3. Create documentation with screenshots
4. Test button workflow
5. Gather user feedback
6. Iterate on UX

---

## Quick Reference Commands

```bash
# After Portal deployment, deploy function code:
cd /Users/bpavan/repos/logint/nr/newrelic-azure-functions
npm run package:logforwarder

FUNCTION_APP=$(az functionapp list \
  --resource-group bpavan-vnet-portal \
  --query "[0].name" -o tsv)

az functionapp deployment source config-zip \
  --resource-group bpavan-vnet-portal \
  --name $FUNCTION_APP \
  --src LogForwarder.zip

# Monitor logs
az webapp log tail --name $FUNCTION_APP --resource-group bpavan-vnet-portal

# Generate traffic
az vm create \
  --resource-group bpavan-vnet-portal \
  --name test-vm \
  --image Ubuntu2204 \
  --size Standard_B1s \
  --vnet-name bpavan-vnet \
  --subnet default \
  --location canadacentral \
  --generate-ssh-keys \
  --public-ip-sku Standard \
  --nsg ""

# Cleanup when done
az group delete --name bpavan-vnet-portal --yes --no-wait
```

---

You're now ready to test the VNet Flow Logs template using the production-style Azure Portal workflow! 🚀