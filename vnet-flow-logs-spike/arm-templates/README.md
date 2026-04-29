# ARM Templates - VNet Flow Logs Forwarder

This folder contains all ARM templates and deployment scripts for the VNet Flow Logs integration.

## 🚀 Quick Start

### For Spikes/POCs (Everything from Scratch) ⭐

**Choose your deployment method:**

#### CLI Deployment (Automated)
```bash
cd complete-setup/cli/
./deploy-complete.sh bpavan-vnet-logs-arm canadacentral
```

#### Portal Deployment (Production-Style UI)
1. Go to: https://portal.azure.com/#create/Microsoft.Template
2. Load: `complete-setup/portal/azuredeploy-vnetflowlogs-complete.json`
3. Fill form and deploy

**Documentation:**
- CLI: [complete-setup/cli/COMPLETE_DEPLOYMENT_GUIDE.md](./complete-setup/cli/COMPLETE_DEPLOYMENT_GUIDE.md)
- Portal: [complete-setup/portal/PORTAL_DEPLOYMENT_GUIDE.md](./complete-setup/portal/PORTAL_DEPLOYMENT_GUIDE.md)

---

### For Production (Existing VNet/Flow Logs)

```bash
cd forwarder-only/
./deploy.sh my-resource-group canadacentral
```

**Read:** [forwarder-only/ARM_DEPLOYMENT_GUIDE.md](./forwarder-only/ARM_DEPLOYMENT_GUIDE.md)

---

## 📂 Folder Structure

```
arm-templates/
├── README.md (this file)
│
├── complete-setup/              # Deploy everything from scratch
│   ├── README.md                # Overview of complete setup
│   ├── cli/                     # CLI deployment (automation)
│   │   ├── azuredeploy-vnetflowlogs-complete.json
│   │   ├── azuredeploy-vnetflowlogs-complete.parameters.json
│   │   ├── deploy-complete.sh
│   │   ├── COMPLETE_DEPLOYMENT_GUIDE.md
│   │   └── IDEMPOTENCY.md
│   └── portal/                  # Portal deployment (UI)
│       ├── azuredeploy-vnetflowlogs-complete.json (symlink)
│       ├── PORTAL_DEPLOYMENT_GUIDE.md
│       └── README.md
│
├── forwarder-only/              # Forwarder only (VNet exists)
│   ├── azuredeploy-vnetflowlogsforwarder.json
│   ├── azuredeploy-vnetflowlogsforwarder.parameters.json
│   ├── deploy.sh
│   ├── ARM_DEPLOYMENT_GUIDE.md
│   └── DEPLOY_CODE.md
│
├── docs/                        # Technical documentation
│   ├── TEMPLATE_COMPARISON.md
│   ├── TECHNICAL_IMPLEMENTATION_COMPARISON.md
│   ├── PARAMETERS_FILE_EXPLANATION.md
│   ├── GENERATE_TRAFFIC.md
│   └── QUICK_START.md
│
└── tools/                       # Diagnostic utilities
    └── diagnose-pipeline.sh
```

---

## 🎯 Which Template Should I Use?

| Scenario | Folder | Deployment Method |
|----------|--------|-------------------|
| **Spike/POC from scratch** | `complete-setup/cli/` | CLI script |
| **Testing Portal workflow** | `complete-setup/portal/` | Azure Portal UI |
| **Learning/Demo** | `complete-setup/cli/` | CLI script |
| **Existing VNet + Flow Logs** | `forwarder-only/` | CLI script |
| **Production (new)** | `complete-setup/` | CLI or Portal |
| **Production (existing)** | `forwarder-only/` | CLI script |

---

## 📚 Navigation

### Complete Setup Options

**📁 [`complete-setup/`](./complete-setup/)**

Deploy everything from scratch:
- **CLI:** Automated script with parameters file → [cli/](./complete-setup/cli/)
- **Portal:** Azure UI form deployment → [portal/](./complete-setup/portal/)

**What it creates:**
- ✅ Virtual Network + Subnet + NSG
- ✅ Network Watcher + **VNet Flow Logs** (targets VNet, not deprecated NSG)
- ✅ Source Storage Account (PT1H.json files)
- ✅ Event Grid System Topic + Subscription (filters PT1H.json)
- ✅ Event Hub Namespace + Event Hub (Basic tier with $Default consumer group)
- ✅ Function App + Internal Storage
- ✅ All RBAC permissions

**Deployment time:** 5-10 minutes

---

### Forwarder Only

**📁 [`forwarder-only/`](./forwarder-only/)**

Deploy forwarder to existing infrastructure.

**Prerequisites:**
- Source Storage Account with VNet Flow Logs
- Network Watcher configured
- Flow Logs enabled

**What it creates:**
- ✅ Event Grid System Topic + Subscription
- ✅ Event Hub Namespace + Event Hub
- ✅ Function App + Internal Storage
- ✅ All connections

**Deployment time:** 3-5 minutes

---

### Documentation

**📁 [`docs/`](./docs/)**

| Document | Description |
|----------|-------------|
| [TEMPLATE_COMPARISON.md](./docs/TEMPLATE_COMPARISON.md) | Compare with BlobForwarder/EventHubForwarder |
| [TECHNICAL_IMPLEMENTATION_COMPARISON.md](./docs/TECHNICAL_IMPLEMENTATION_COMPARISON.md) | How ARM templates work internally |
| [PARAMETERS_FILE_EXPLANATION.md](./docs/PARAMETERS_FILE_EXPLANATION.md) | Why use parameters files |
| [GENERATE_TRAFFIC.md](./docs/GENERATE_TRAFFIC.md) | Test the E2E pipeline |
| [QUICK_START.md](./docs/QUICK_START.md) | Quick reference |

---

### Tools

**📁 [`tools/`](./tools/)**

| Tool | Description |
|------|-------------|
| [diagnose-pipeline.sh](./tools/diagnose-pipeline.sh) | Check pipeline health |

```bash
cd tools/
./diagnose-pipeline.sh
```

---

## 📝 After Deployment

**Both templates require manual code deployment:**

```bash
cd /Users/bpavan/repos/logint/nr/newrelic-azure-functions

# Package code
npm run package:logforwarder

# Get function app name
FUNCTION_APP_NAME=$(az functionapp list \
  --resource-group <your-resource-group> \
  --query "[0].name" -o tsv)

# Deploy code
az functionapp deployment source config-zip \
  --resource-group <your-resource-group> \
  --name $FUNCTION_APP_NAME \
  --src LogForwarder.zip

# Restart
az functionapp restart \
  --resource-group <your-resource-group> \
  --name $FUNCTION_APP_NAME
```

**See:** [forwarder-only/DEPLOY_CODE.md](./forwarder-only/DEPLOY_CODE.md) for detailed instructions.

---

## 🔄 Deployment Method Comparison

### CLI vs Portal

| Aspect | CLI | Portal |
|--------|-----|--------|
| **Location** | `complete-setup/cli/` | `complete-setup/portal/` |
| **Method** | `./deploy-complete.sh` | Browser UI form |
| **Parameters** | Parameters file (JSON) | Fill form fields |
| **Target User** | Developers, DevOps | Business users, non-technical |
| **Speed** | Fast (one command) | Slower (manual) |
| **Repeatability** | Excellent | Manual each time |
| **Automation** | Yes (CI/CD) | No |
| **Best For** | Development, testing | Production, self-service |

**Both deploy the same infrastructure!**

---

## 🔄 Template Comparison

### Complete vs Forwarder Only

| Feature | Complete | Forwarder Only |
|---------|----------|----------------|
| **Location** | `complete-setup/` | `forwarder-only/` |
| **Deployment Time** | 10-15 min | 5-10 min |
| **Prerequisites** | None | VNet + Flow Logs |
| **VNet/NSG** | ✅ Creates | ❌ Must exist |
| **Flow Logs** | ✅ Configures | ❌ Must exist |
| **Source Storage** | ✅ Creates | ❌ Must exist |
| **Event Grid** | ✅ Creates | ✅ Creates |
| **Event Hub** | ✅ Creates | ✅ Creates |
| **Function App** | ✅ Creates | ✅ Creates |
| **Role Assignment** | ✅ Automatic | ⚠️  Manual step |
| **Use Case** | Spike/POC | Production |

---

## ⚡ Testing the E2E Flow

After deployment, generate traffic and test:

**1. Generate Traffic:**
```bash
az vm create \
  --resource-group YOUR_RESOURCE_GROUP \
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

**2. Monitor Function Logs:**
- Portal: Function App → Log stream
- CLI: `az webapp log tail --name FUNCTION_APP --resource-group RG`

**3. Verify in New Relic:**
```sql
SELECT * FROM Log
WHERE logtype = 'azure.vnet.flowlog'
SINCE 30 minutes ago
```

**See:** [docs/GENERATE_TRAFFIC.md](./docs/GENERATE_TRAFFIC.md) for complete testing guide.

---

## 🆘 Need Help?

### By Deployment Method

- **CLI deployment:** [complete-setup/cli/COMPLETE_DEPLOYMENT_GUIDE.md](./complete-setup/cli/COMPLETE_DEPLOYMENT_GUIDE.md)
- **Portal deployment:** [complete-setup/portal/PORTAL_DEPLOYMENT_GUIDE.md](./complete-setup/portal/PORTAL_DEPLOYMENT_GUIDE.md)
- **Forwarder only:** [forwarder-only/ARM_DEPLOYMENT_GUIDE.md](./forwarder-only/ARM_DEPLOYMENT_GUIDE.md)

### By Topic

- **Code deployment:** [forwarder-only/DEPLOY_CODE.md](./forwarder-only/DEPLOY_CODE.md)
- **Troubleshooting:** [tools/diagnose-pipeline.sh](./tools/diagnose-pipeline.sh)
- **Architecture:** [docs/TEMPLATE_COMPARISON.md](./docs/TEMPLATE_COMPARISON.md)
- **Testing:** [docs/GENERATE_TRAFFIC.md](./docs/GENERATE_TRAFFIC.md)

---

## 💡 Key Concepts

### VNet Flow Logs (New Standard)

**Important:** These templates use **VNet-level Flow Logs**, not NSG Flow Logs.

- ✅ VNet Flow Logs are the new Azure standard
- ❌ NSG Flow Logs are being retired (September 2027)
- ✅ Creation of new NSG flow logs blocked since June 2025

**Migration guide:** https://learn.microsoft.com/azure/network-watcher/nsg-flow-logs-migrate

### Idempotency

All templates are idempotent using `uniqueString(resourceGroup().id)`:
- ✅ Same resource group = same resource names
- ✅ Safe to re-run deployment
- ✅ No duplicate resources

See [complete-setup/cli/IDEMPOTENCY.md](./complete-setup/cli/IDEMPOTENCY.md) for details.

---

## 💰 Cost Estimate

**Complete Setup:** ~$21-50/month
- Function App (Consumption): ~$0
- Storage Accounts (2): ~$20
- Event Hub (Basic): ~$0.015
- Event Grid: ~$0.60
- Flow Logs: ~$0.60/GB ingested

**Forwarder Only:** ~$11-31/month
- Same as above minus VNet/Flow Logs costs

---

**Back to main spike documentation:** [../README.md](../README.md)