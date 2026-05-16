# Complete Setup - VNet Flow Logs to New Relic

This folder contains templates and guides for deploying the **complete VNet Flow Logs infrastructure** from scratch.

## What Gets Deployed

The complete setup creates:
- ✅ Virtual Network + Subnet + NSG
- ✅ VNet Flow Logs (targets VNet, not deprecated NSG flow logs)
- ✅ Source Storage Account (for PT1H.json files)
- ✅ Event Grid System Topic + Subscription (with PT1H.json filtering)
- ✅ Event Hub Namespace + Event Hub (Basic tier)
- ✅ Function App + Internal Storage
- ✅ Application Insights
- ✅ All RBAC permissions

## Deployment Methods

Choose your deployment method:

### 1. CLI Deployment (Automation/DevOps)

**📁 Location:** [`cli/`](./cli/)

Best for:
- Repeated deployments during development/testing
- CI/CD pipelines
- Infrastructure as Code
- Automated testing

**Quick Start:**
```bash
cd cli/
./deploy-complete.sh bpavan-vnet-logs-arm canadacentral
```

**Documentation:**
- [COMPLETE_DEPLOYMENT_GUIDE.md](./cli/COMPLETE_DEPLOYMENT_GUIDE.md) - Full CLI workflow
- [IDEMPOTENCY.md](./cli/IDEMPOTENCY.md) - How safe re-runs work

**Key Files:**
- `azuredeploy-vnetflowlogs-complete.json` - ARM template
- `azuredeploy-vnetflowlogs-complete.parameters.json` - Pre-configured parameters
- `deploy-complete.sh` - Automated deployment script

---

### 2. Portal Deployment (Production User Experience)

**📁 Location:** [`portal/`](./portal/)

Best for:
- Testing production user workflows
- Self-service deployments
- Non-developers
- One-time setup

**Quick Start:**
1. Go to: https://portal.azure.com/#create/Microsoft.Template
2. Load template: `azuredeploy-vnetflowlogs-complete.json`
3. Fill UI form (11 parameters)
4. Deploy!

**Documentation:**
- [PORTAL_DEPLOYMENT_GUIDE.md](./portal/PORTAL_DEPLOYMENT_GUIDE.md) - Complete Portal workflow

**Key Files:**
- `azuredeploy-vnetflowlogs-complete.json` (symlink to CLI template)

---

## After Infrastructure Deployment

**Important:** Both methods create infrastructure but **don't deploy function code**.

You must manually deploy the function code:

```bash
cd /Users/bpavan/repos/logint/nr/newrelic-azure-functions
npm run package:logforwarder

az functionapp deployment source config-zip \
  --resource-group YOUR_RESOURCE_GROUP \
  --name YOUR_FUNCTION_APP \
  --src LogForwarder.zip
```

See [../docs/GENERATE_TRAFFIC.md](../docs/GENERATE_TRAFFIC.md) for testing the E2E flow.

---

## Comparison: CLI vs Portal

| Aspect | CLI | Portal |
|--------|-----|--------|
| **Target User** | Developers, DevOps | Business users, non-technical |
| **Deployment Speed** | Fast (one command) | Slower (form filling) |
| **Repeatability** | Excellent (parameters file) | Manual each time |
| **Automation** | Yes (CI/CD ready) | No |
| **Learning Curve** | Requires CLI knowledge | Intuitive UI |
| **Best For** | Development, testing | Production setup, self-service |

---

## Related Resources

- **Tools:** [`../tools/`](../tools/) - Diagnostic scripts
- **Documentation:** [`../docs/`](../docs/) - Technical deep dives
- **Forwarder Only:** [`../forwarder-only/`](../forwarder-only/) - Infrastructure already exists

---

## Cost Estimate

Complete setup costs approximately **$21-50/month**:
- Function App (Consumption): ~$0/month
- Storage Accounts (2): ~$20/month
- Event Hub (Basic): ~$0.015/month
- Event Grid: ~$0.60/month
- VNet/NSG: ~$0
- Flow Logs: ~$0.60/GB ingested

See Azure pricing calculator for exact costs based on your usage.

---

## Quick Reference

```bash
# CLI Deployment
cd cli/
./deploy-complete.sh my-resource-group canadacentral

# Deploy function code
npm run package:logforwarder
az functionapp deployment source config-zip \
  --resource-group my-resource-group \
  --name FUNCTION_APP_NAME \
  --src LogForwarder.zip

# Diagnostic check
cd ../tools/
./diagnose-pipeline.sh

# Generate traffic for testing
# See ../docs/GENERATE_TRAFFIC.md
```

---

## Support

- **Issues:** Report in main repo
- **Documentation:** See `docs/` folder
- **Template Comparison:** See `docs/TEMPLATE_COMPARISON.md`
