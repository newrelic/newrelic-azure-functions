# VNet Flow Logs Forwarder - Spike Documentation

This folder contains all documentation and artifacts for the VNet Flow Logs integration spike.

## 📚 Documentation Index

### 🎯 Start Here

**[QUICK_START.md](./QUICK_START.md)** ⭐ **NEW - ARM Template Deployment**
- **What**: Complete step-by-step guide to deploy using ARM template (11-18 minutes)
- **When to use**: You want to deploy the same setup as manual in a new resource group
- **Contains**: Infrastructure deployment + manual code upload workflow

**[COMPLETE_SETUP_OVERVIEW.md](./COMPLETE_SETUP_OVERVIEW.md)**
- **What**: Complete end-to-end setup guide from VNet creation to New Relic
- **When to read**: First - if you're starting from scratch or want the big picture
- **Contains**: Full data flow, all resources, time estimates, validation checkpoints

**[SPIKE_SUMMARY_VNetFlowLogs.md](./SPIKE_SUMMARY_VNetFlowLogs.md)**
- **What**: Executive summary of spike findings
- **When to read**: To understand architectural decisions and implementation gaps
- **Contains**: Architecture decisions, implementation gaps, timeline, risks

---

### 🚀 Implementation Guides

#### Option 1: Manual Azure Portal Setup (Recommended for Learning)

**[MANUAL_UI_SETUP_GUIDE.md](./MANUAL_UI_SETUP_GUIDE.md)**
- **What**: Step-by-step Azure Portal UI guide
- **When to use**: Creating resources manually through Azure Portal
- **Time**: 1-2 hours
- **Best for**: Understanding how everything connects, first-time setup

**[RESOURCE_LINKAGE_MAP.md](./RESOURCE_LINKAGE_MAP.md)**
- **What**: Visual reference showing how resources connect
- **When to use**: Quick reference while setting up manually
- **Contains**: Connection diagrams, configuration values, common mistakes

#### Option 2: ARM Template Deployment (Automated)

All ARM templates and deployment scripts are in the **[arm-templates/](./arm-templates/)** folder.

##### **Option 2A: Complete Setup from Scratch** ⭐ **BEST FOR SPIKES/POCs**

**[arm-templates/COMPLETE_DEPLOYMENT_GUIDE.md](./arm-templates/COMPLETE_DEPLOYMENT_GUIDE.md)** ⭐ **START HERE**
- **What**: Single ARM template that creates EVERYTHING including prerequisites
- **When to use**: Starting from scratch, running spikes/POCs
- **Time**: 10-15 minutes (automated) + 2 min code deployment
- **Creates**: VNet + NSG + Flow Logs + Event Grid + Event Hub + Function App + All permissions
- **Usage**: `cd arm-templates && ./deploy-complete.sh vnetflowlogs-complete-demo canadacentral`

##### **Option 2B: Forwarder Only (Existing VNet/Flow Logs)**

**[arm-templates/QUICK_START.md](./arm-templates/QUICK_START.md)**
- **What**: Step-by-step ARM deployment for existing infrastructure
- **When to use**: You already have VNet and Flow Logs running
- **Time**: 11-18 minutes total
- **Usage**: `cd arm-templates && ./deploy.sh bpavan-vnet-logs-arm canadacentral`

**[arm-templates/ARM_DEPLOYMENT_GUIDE.md](./arm-templates/ARM_DEPLOYMENT_GUIDE.md)**
- **What**: Comprehensive ARM template deployment documentation
- **Contains**: All deployment methods, troubleshooting, comparison with manual

**[arm-templates/DEPLOY_CODE.md](./arm-templates/DEPLOY_CODE.md)**
- **What**: Guide for deploying function code after ARM template
- **Contains**: Package creation, deployment commands, verification

**[README-vnetflowlogsforwarder.md](./README-vnetflowlogsforwarder.md)**
- **What**: ARM template technical documentation
- **Contains**: Parameters reference, architecture, cost estimates

---

### 🧪 Testing & Validation

**[SPIKE_VALIDATION_GUIDE.md](./SPIKE_VALIDATION_GUIDE.md)**
- **What**: How to validate the ARM template spike
- **Contains**: 4 validation levels (syntax, what-if, deployment, integration)
- **When to use**: After creating ARM template, before deploying to production

**[MVP_PLAN.md](./MVP_PLAN.md)**
- **What**: Minimum Viable Product strategy
- **When to use**: Planning incremental implementation
- **Contains**: Simplified setup, MVP function code, timeline

---

## 🗺️ Quick Navigation

### I want to...

| Goal | Start Here |
|------|------------|
| **Deploy COMPLETE setup from scratch (SPIKE/POC)** ⭐ | [arm-templates/COMPLETE_DEPLOYMENT_GUIDE.md](./arm-templates/COMPLETE_DEPLOYMENT_GUIDE.md) |
| **Deploy using ARM template (existing VNet)** | [arm-templates/QUICK_START.md](./arm-templates/QUICK_START.md) |
| **See the complete picture (VNet to New Relic)** | [COMPLETE_SETUP_OVERVIEW.md](./COMPLETE_SETUP_OVERVIEW.md) |
| **Set up from scratch (includes VNet setup)** | [MANUAL_UI_SETUP_GUIDE.md](./MANUAL_UI_SETUP_GUIDE.md) → Start at Step 0 |
| **Set up with existing VNet & Flow Logs** | [MANUAL_UI_SETUP_GUIDE.md](./MANUAL_UI_SETUP_GUIDE.md) → Skip to Step 1 |
| **Understand the spike** | [SPIKE_SUMMARY_VNetFlowLogs.md](./SPIKE_SUMMARY_VNetFlowLogs.md) |
| **Deploy code after ARM template** | [arm-templates/DEPLOY_CODE.md](./arm-templates/DEPLOY_CODE.md) |
| **See how resources link** | [RESOURCE_LINKAGE_MAP.md](./RESOURCE_LINKAGE_MAP.md) |
| **Build an MVP quickly** | [MVP_PLAN.md](./MVP_PLAN.md) |
| **Validate the template** | [SPIKE_VALIDATION_GUIDE.md](./SPIKE_VALIDATION_GUIDE.md) |

---

## 📋 File Descriptions

### Documentation Files

| File | Type | Lines | Purpose |
|------|------|-------|---------|
| `COMPLETE_SETUP_OVERVIEW.md` | Overview | ~450 | Complete end-to-end setup (VNet to New Relic) |
| `MANUAL_UI_SETUP_GUIDE.md` | Guide | ~650 | Step-by-step Portal UI (includes VNet setup) |
| `SPIKE_SUMMARY_VNetFlowLogs.md` | Summary | ~380 | Spike findings, decisions, gaps |
| `RESOURCE_LINKAGE_MAP.md` | Reference | ~380 | Visual connection diagrams |
| `MVP_PLAN.md` | Plan | ~480 | Simplified MVP implementation |
| `SPIKE_VALIDATION_GUIDE.md` | Guide | ~450 | Template validation procedures |
| `README-vnetflowlogsforwarder.md` | Docs | ~585 | ARM template technical documentation |

### ARM Templates & Deployment (in `arm-templates/` folder)

| File | Type | Lines | Purpose |
|------|------|-------|---------|
| **Complete Setup (Spike/POC)** ||||
| `arm-templates/COMPLETE_DEPLOYMENT_GUIDE.md` ⭐ | Guide | ~350 | **Complete setup from scratch guide** |
| `arm-templates/azuredeploy-vnetflowlogs-complete.json` ⭐ | ARM Template | ~600 | **VNet + Flow Logs + Forwarder** |
| `arm-templates/azuredeploy-vnetflowlogs-complete.parameters.json` ⭐ | Parameters | ~40 | Parameters for complete template |
| `arm-templates/deploy-complete.sh` ⭐ | Script | ~220 | **One-command complete deployment** |
| **Forwarder Only (Existing Infrastructure)** ||||
| `arm-templates/QUICK_START.md` | Guide | ~200 | Fast ARM deployment (existing VNet) |
| `arm-templates/ARM_DEPLOYMENT_GUIDE.md` | Guide | ~580 | Comprehensive ARM deployment docs |
| `arm-templates/DEPLOY_CODE.md` | Guide | ~200 | Manual code deployment after ARM |
| `arm-templates/azuredeploy-vnetflowlogsforwarder.json` | ARM Template | ~875 | Forwarder only (requires existing VNet) |
| `arm-templates/azuredeploy-vnetflowlogsforwarder.parameters.json` | Parameters | ~50 | Parameters for forwarder-only |
| `arm-templates/deploy.sh` | Script | ~250 | Bash deployment script |
| `arm-templates/deploy.ps1` | Script | ~230 | PowerShell deployment script |

**Total**: ~4,280 lines of documentation + 1,795 lines of ARM/scripts = **6,075 lines**

---

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    EXISTING RESOURCES                        │
│   Network Watcher → Storage Account (Source)                │
│                      └── PT1H.json files                     │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                  RESOURCES TO CREATE                         │
│                                                              │
│   Event Grid System Topic                                   │
│          ↓                                                   │
│   Event Grid Subscription (filters PT1H.json)               │
│          ↓                                                   │
│   Event Hub (ordered queue)                                 │
│          ↓                                                   │
│   Azure Function (stateful processing)                      │
│          ↓                                                   │
│   Table Storage (cursor tracking)                           │
│          ↓                                                   │
│   New Relic Logs API                                        │
└─────────────────────────────────────────────────────────────┘
```

---

## ✅ What's Included in This Spike

### Infrastructure (ARM Template)
- ✅ Event Grid System Topic + Subscription
- ✅ Event Hub Namespace + Event Hub + Consumer Group
- ✅ Azure Function App with Managed Identity
- ✅ Internal Storage Account (includes Table Storage for cursors)
- ✅ Optional Private VNet deployment
- ✅ Two deployment modes: Basic (Consumption) and Enterprise (Premium)

### Documentation
- ✅ Spike summary with architectural decisions
- ✅ Complete manual setup guide (Azure Portal UI)
- ✅ Resource linkage diagrams and reference
- ✅ ARM template deployment guide
- ✅ Validation and testing procedures
- ✅ MVP implementation strategy

---

## ❌ What's NOT Included (Implementation Gaps)

These require additional development:

### 1. Function Code
- ❌ Event Hub trigger registration in `LogForwarder/index.js`
- ❌ VNet Flow Logs handler implementation
- ❌ Table Storage cursor read/write logic
- ❌ Delta extraction using block list API
- ❌ VNet Flow Logs JSON parsing

**Estimated Effort**: 6-9 days

### 2. Testing
- ❌ Unit tests
- ❌ Integration tests
- ❌ Performance testing
- ❌ Zero duplication validation

**Estimated Effort**: 2-3 days

### 3. Advanced Features
- ❌ State loss recovery mechanism
- ❌ Dead letter queue
- ❌ Advanced monitoring/alerting
- ❌ Multi-NSG support

**Estimated Effort**: 3-4 days

---

## 📅 Implementation Timeline

### Phase 1: Infrastructure (✅ Complete)
- **Status**: Done (this spike)
- **Time**: 5 hours
- **Deliverables**: ARM template + documentation

### Phase 2: Function Code (⏳ Pending)
- **Status**: Not started
- **Time**: 6-9 days
- **Deliverables**: Working end-to-end pipeline

### Phase 3: Testing (⏳ Pending)
- **Status**: Not started
- **Time**: 2-3 days
- **Deliverables**: Test suite, validation

### Phase 4: Production Readiness (⏳ Pending)
- **Status**: Not started
- **Time**: 3-4 days
- **Deliverables**: Monitoring, documentation, release

**Total Estimated Effort**: 11-16 days from infrastructure to production

---

## 🎯 Success Criteria

### Spike Success (✅ Achieved)
- ✅ ARM template validates successfully
- ✅ Architecture design is sound
- ✅ All resources can be created
- ✅ Resource linkages are correct
- ✅ Comprehensive documentation exists

### MVP Success (⏳ Next Step)
- ⏳ Events flow from Event Grid → Event Hub → Function
- ⏳ Function can read blobs using Managed Identity
- ⏳ Logs appear in New Relic
- ⏳ Basic end-to-end validation works

### Production Success (⏳ Future)
- ⏳ Delta extraction eliminates duplication
- ⏳ State management handles failures gracefully
- ⏳ Performance meets requirements (1000+ VMs)
- ⏳ Comprehensive testing coverage
- ⏳ Monitoring and alerting operational

---

## 💰 Cost Estimates

### Basic Deployment (100 VMs)
- **Monthly Cost**: ~$46
- **Breakdown**: Function ($20) + Event Hub ($20) + Storage ($5) + Event Grid ($1)

### Enterprise Deployment (1000+ VMs)
- **Monthly Cost**: ~$390
- **Breakdown**: Function EP1 ($160) + Event Hub auto-inflate ($200) + Storage ($20) + Event Grid ($10)

---

## 🔗 Related Documentation

### Repository Structure
```
newrelic-azure-functions/
├── vnet-flow-logs-spike/               ← You are here
│   ├── README.md                       ← This file
│   ├── SPIKE_SUMMARY_VNetFlowLogs.md
│   ├── MANUAL_UI_SETUP_GUIDE.md
│   ├── RESOURCE_LINKAGE_MAP.md
│   ├── MVP_PLAN.md
│   ├── SPIKE_VALIDATION_GUIDE.md
│   ├── COMPLETE_SETUP_OVERVIEW.md
│   ├── README-vnetflowlogsforwarder.md
│   └── arm-templates/                  ← ARM templates & deployment
│       ├── COMPLETE_DEPLOYMENT_GUIDE.md          ⭐ Complete setup
│       ├── azuredeploy-vnetflowlogs-complete.json ⭐ Complete template
│       ├── azuredeploy-vnetflowlogs-complete.parameters.json
│       ├── deploy-complete.sh                     ⭐ One-command deploy
│       ├── QUICK_START.md                         Forwarder only
│       ├── ARM_DEPLOYMENT_GUIDE.md
│       ├── DEPLOY_CODE.md
│       ├── azuredeploy-vnetflowlogsforwarder.json
│       ├── azuredeploy-vnetflowlogsforwarder.parameters.json
│       ├── deploy.sh
│       └── deploy.ps1
│
├── armTemplates/                       ← Other ARM templates
│   ├── azuredeploy-blobforwarder.json
│   └── azuredeploy-eventhubforwarder.json
│
├── LogForwarder/                       ← Function code (has VNet handler)
│   ├── index.js
│   ├── BlobForwarder/
│   └── EventHubForwarder/
│
├── docs/
│   └── CHANGELOG.md
│
└── README.md                           ← Main project README
```

### External References
- [DACI Document](https://newrelic.atlassian.net/wiki/spaces/TDP/pages/5401018886/DACI+Azure+VNet+Flow+Logs+Integration)
- [CDD Document](https://newrelic.atlassian.net/wiki/spaces/TDP/pages/5439947055/CDD+Draft+Azure+VNET+Flow+Logs)
- [Jira Epic](https://new-relic.atlassian.net/browse/NR-542850)

---

## 🤝 Contributing

### Next Steps for Contributors

1. **Review Spike Summary** → Understand architectural decisions
2. **Choose Path**:
   - **Quick Validation**: Use manual setup to test E2E
   - **Production Path**: Deploy ARM template and build function code
3. **Implement Function Code** → Follow MVP_PLAN.md
4. **Add Tests** → Unit + integration tests
5. **Production Readiness** → Monitoring, docs, release

### Questions or Issues?

- Review the spike summary for context
- Check the appropriate guide for your use case
- Refer to architecture diagrams for understanding linkages

---

## 📄 License

This spike is part of the `newrelic-azure-functions` project.
See the main repository for license information.

---

**Spike Completed**: April 23, 2026
**Status**: Infrastructure design complete, function code pending
**Next Action**: Implement VNet Flow Logs handler in `LogForwarder/index.js`