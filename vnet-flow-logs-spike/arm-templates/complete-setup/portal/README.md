# Portal Deployment - VNet Flow Logs

Deploy VNet Flow Logs infrastructure using the **Azure Portal UI** - the production user experience.

## Quick Start

### 1. Open Azure Portal

Go to: **https://portal.azure.com/#create/Microsoft.Template**

Or search: "Deploy a custom template" in Azure Portal

### 2. Load Template

1. Click **"Build your own template in the editor"**
2. Copy content from `azuredeploy-vnetflowlogs-complete.json`
3. Paste into editor
4. Click **"Save"**

### 3. Fill Form

Azure generates a UI form with these parameters:

```
Project Details:
├─ Subscription: [Your subscription]
└─ Resource group: [Create new: bpavan-vnet-portal]

Instance Details:
├─ Region: [Canada Central]
└─ Location: [leave blank]

New Relic:
├─ License Key: [d377ad18ef50788f2341ed78fa6c853765a1NRAL]
├─ Endpoint: [https://log-api.newrelic.com/log/v1]
└─ Custom Attributes: [optional]

Network:
├─ VNet Name: [bpavan-vnet]
├─ VNet CIDR: [10.1.0.0/16]
├─ Subnet Name: [default]
└─ Subnet CIDR: [10.1.0.0/24]

Flow Logs:
└─ Retention Days: [7]

Event Hub:
├─ Max Batch: [20]
├─ Min Batch: [5]
└─ Max Wait: [00:00:30]
```

### 4. Deploy

1. Click **"Review + create"**
2. Click **"Create"**
3. Wait 5-10 minutes

### 5. Deploy Function Code

```bash
cd /Users/bpavan/repos/logint/nr/newrelic-azure-functions
npm run package:logforwarder

FUNCTION_APP=$(az functionapp list \
  --resource-group bpavan-vnet-portal \
  --query "[0].name" -o tsv)

az functionapp deployment source config-zip \
  --resource-group bpavan-vnet-portal \
  --name $FUNCTION_APP \
  --src LogForwarder.zip
```

### 6. Test

See [../../docs/GENERATE_TRAFFIC.md](../../docs/GENERATE_TRAFFIC.md)

---

## Complete Guide

See **[PORTAL_DEPLOYMENT_GUIDE.md](./PORTAL_DEPLOYMENT_GUIDE.md)** for:
- Detailed step-by-step walkthrough
- Screenshots and form field descriptions
- Troubleshooting common issues
- "Deploy to Azure" button setup
- Testing E2E flow
- Production recommendations

---

## Why Portal Deployment?

✅ **Production user experience** - Test how real users will deploy
✅ **Self-service** - No CLI knowledge required
✅ **Intuitive** - Form-based, guided workflow
✅ **Validation** - Azure validates parameters before deployment

---

## Files in This Folder

- `azuredeploy-vnetflowlogs-complete.json` - ARM template (symlink to ../cli/)
- `PORTAL_DEPLOYMENT_GUIDE.md` - Complete deployment guide
- `README.md` - This file

---

## Quick Comparison

| CLI Deployment | Portal Deployment |
|----------------|-------------------|
| `./deploy-complete.sh` | Click buttons in browser |
| Parameters file | Fill UI form |
| Fast (automation) | Slower (manual) |
| Developer-focused | User-focused |

Both deploy the **same infrastructure** - just different methods!

---

## Need Help?

- **Full Guide:** [PORTAL_DEPLOYMENT_GUIDE.md](./PORTAL_DEPLOYMENT_GUIDE.md)
- **CLI Alternative:** [../cli/](../cli/)
- **Documentation:** [../../docs/](../../docs/)