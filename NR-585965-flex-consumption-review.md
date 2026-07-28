# NR-585965 — Add Flex Consumption to the Event Hub forwarder (ARM)

Reviewer guide for the changes to `armTemplates/azuredeploy-eventhubforwarder.json`.

## Summary

The Event Hub forwarder template today supports three hosting plans (ElasticPremium / Basic / Consumption), but the customer never picks one — it's *inferred* from `scalingMode` + `disablePublicAccessToStorageAccount`, and there's no Flex Consumption option.

This change:
- Adds a `functionAppPlan` parameter so the plan is a **direct choice** of four values.
- Adds **FlexConsumption (FC1)** as the fourth plan and the new **default**.
- Replaces the plan-guessing logic with a single `planConfig` lookup table (one row per plan), matching the pattern shipped for the VNet Flow Logs forwarder.
- Adds the supporting resources Flex needs (code-delivery container + script, storage RBAC, private-networking wiring).

Application code (`LogForwarder/index.js`) is **not touched** — this is deploy-time only.

### References
- Ticket: NR-585965 (parent NR-581117, Azure Logs Integration NorthStar)
- Pattern source: `newrelic/azure-vnet-flow-logs` PR #26 (merged) + its DACI ("Multiple app service plans support in VNet Flow logs")
- Approach confirmed with Pavan: mirror the four-plan pattern, Flex as default.

## The design

`scalingMode` used to do two jobs: pick the plan **and** inflate the Event Hub. This change removes only the first job — plan selection moves to `functionAppPlan`. `scalingMode` still controls Event Hub inflation (auto-inflate / throughput units / partitions) and per-plan scale (instance/worker counts), unchanged.

**Before** (variables):
```
isHighScalabing / basicScaleConfig / aspConfig   → picked one of 3 ASP variables
```
**After**:
```
planConfig { FlexConsumption, ElasticPremium, Basic, Consumption }   ← 4-row table
pc = planConfig[functionAppPlan]                                     ← the chosen row
```
Every resource reads `pc.<field>` and stays plan-agnostic. The three existing plans' specs are reproduced verbatim in their rows (backward compatible); only FlexConsumption is new.

## Parameter & variable changes

- **Added parameter** `functionAppPlan` — `[FlexConsumption (default), ElasticPremium, Basic, Consumption]`.
- **Added variables**: `planConfig`, `pc`, `runFromPackageSetting`; role IDs (`storageBlobDataOwnerRoleId`, `storageQueueDataContributorRoleId`, `storageTableDataContributorRoleId`, `websiteContributorRoleId`, `storageFileDataPrivilegedContributorRoleId`); names (`deploymentIdentityName`, `deploymentScriptName`, `deploymentScriptsSubnetName`/`Id`, `sitesPrivateDnsZoneName`/`LinkName`, `functionAppPrivateEndpointName`/`DnsZoneGroupName`).
- **Removed variable**: `functionNetworkConfigName` (dead after removing `networkConfig`).
- **Trimmed `baseAppSettings`**: removed `FUNCTIONS_WORKER_RUNTIME`, `WEBSITE_NODE_DEFAULT_VERSION`, `WEBSITE_RUN_FROM_PACKAGE` — now applied per-plan (Flex sets runtime via `functionAppConfig`; the other three get worker-runtime settings; WRFP is conditional).

## Resources — added / modified / removed

### Added
| Resource | Condition | Purpose |
|---|---|---|
| Validator `deploymentScripts` | Consumption + private | Fails fast with a clear message on the unsupported combo; function app depends on it. |
| `blobServices` + `deployments` container | always | Where Flex stores/reads its code. |
| 3× `roleAssignments` (Blob Owner, Queue + Table Contributor) | always | Function app identity → its own storage (needed for identity host storage + Flex code fetch). |
| `userAssignedIdentities` (deployment identity) | Flex | Identity the code-push script runs as. |
| `roleAssignments` (Website Contributor) | Flex | Lets that identity push code to the app. |
| Flex `deploymentScripts` | Flex | Runs `az functionapp deployment source config-zip` to push `LogForwarder.zip`. |
| `deployment-scripts-subnet` | (subnet, used when private) | Runs the deploy script inside the VNet in private mode. |
| `roleAssignments` (Storage File Data Privileged Contributor) | Flex + private | Deploy script mounts the storage file share. |
| Function-app private endpoint + `privatelink.azurewebsites.net` DNS zone + VNet link + zone group | Flex + private | Inbound path so the deploy script can reach the app when its public access is off. |

### Modified
| Resource | Change |
|---|---|
| `serverfarms` (service plan) | Reads `pc.kind/sku/properties` instead of `aspConfig`. |
| `sites` (function app) | Plan-aware `kind` (Linux for Flex, Windows otherwise), always system-assigned identity, `reserved`, `functionAppConfig` (Flex only), `union()`-composed `siteConfig` with per-plan app settings, inline `virtualNetworkSubnetId`, `vnetRouteAllEnabled` (Flex+private only), plan-safe `alwaysOn`. |
| `sites/extensions` (ZipDeploy) | Condition now `public && pc.usesRunFromPackage` — excludes Flex. |
| VNet subnet | `delegations` now plan-aware (`Microsoft.App/environments` for Flex, `Microsoft.Web/serverFarms` for EP/Basic, none for Consumption). |

### Removed
| Resource | Why |
|---|---|
| `sites/networkConfig` | VNet integration moved to inline `virtualNetworkSubnetId` on the function app (matches the VNet forwarder's model). |

## Plan behavior matrix

| Plan | SKU / OS | Code delivery | VNet delegation |
|---|---|---|---|
| FlexConsumption (default) | FC1 / Linux | deploy script → `deployments` container | `Microsoft.App/environments` |
| ElasticPremium | EP1 / Windows | ZipDeploy (public) / WRFP (private) | `Microsoft.Web/serverFarms` |
| Basic | B1 / Windows | ZipDeploy (public) / WRFP (private) | `Microsoft.Web/serverFarms` |
| Consumption | Y1 / Windows | ZipDeploy (public); private is blocked | none |

## Comparison to the VNet forwarder (PR #26)

Legend: ✅ same · 🔧 same idea, adapted to EH · ⚠️ intentionally different / EH-specific

| Change | vs VNet | Notes |
|---|---|---|
| `functionAppPlan` param (4 values, Flex default) | ✅ | Identical |
| `planConfig` + `pc` lookup | ✅ | Same structure; non-Flex rows reproduce EH's existing ASP specs |
| `runFromPackageSetting` | ✅ | Identical |
| Trim base app settings → per-plan | ✅ | Same approach |
| Service plan reads `pc` | ✅ | Identical |
| Function app: kind / identity / reserved / functionAppConfig / inline VNet / vnetRouteAll | ✅ | Same structure |
| Host storage auth (identity in MI mode) | ✅ | Matches VNet + DACI |
| 3 storage role grants (blob / queue / table) | ✅ | Identical |
| Deployment identity + Website Contributor | ✅ | Identical |
| Flex deploy script (`config-zip`) | ✅ | Identical |
| ZipDeploy excludes Flex | ✅ | Identical |
| Subnet delegation plan-aware | ✅ | Identical logic |
| Validator (Consumption + private) | ✅ | Identical |
| deployment-scripts subnet | ✅ | Same; EH uses `10.2.2.0/28` (its own address space) |
| Storage File role on deploy identity | ✅ | Same; gated on Flex+private in EH (deploy identity is Flex-only) |
| Script container / storage settings (private) | ✅ | Identical |
| `deployments` container | 🔧 | VNet has a dedicated *function* storage account; EH has one storage account, so the container sits there |
| Function app: app-setting **contents** | 🔧 | Structure identical; settings differ (`EVENTHUB_*` / `NR_*` vs flow-log settings — different apps) |
| Function-app private endpoint + sites DNS | 🔧 | Same shape; EH gates on Flex+private and uses literal `privatelink.azurewebsites.net` (Flex isn't in Gov cloud) |
| Function app: `alwaysOn` | ⚠️ | VNet sets it only on the Basic row (always true). EH keeps its **current** rule — `alwaysOn = private` for all non-Flex, Flex excluded — to avoid changing existing behavior. |
| `networkConfig` removal | ⚠️ | EH-only change: VNet never had this resource. Removing it converges EH onto VNet's inline `virtualNetworkSubnetId` model. |
| Source-storage Blob Data Reader role | ⚠️ omitted | VNet-only (reads flow-log *source* blobs). EH reads from the Event Hub, so not needed. |
| Event Grid delivery-identity rework | ⚠️ omitted | VNet-specific. EH's activity-log Event Grid path is left untouched. |

**Net:** the Flex machinery is a faithful port. The only deliberate divergences are `alwaysOn` (preserves EH's existing behavior) and the `networkConfig` removal (EH catching up to VNet's model); two VNet role/identity pieces are correctly omitted because EH doesn't need them.

## Behavior changes reviewers should scrutinize

1. **Default plan flips to FlexConsumption.** EH's previous default was Consumption (Y1). An existing customer who redeploys *without setting `functionAppPlan`* now gets Flex — a different tier family, which Azure cannot change in place. **This needs a product decision** (default Flex per the ticket, vs. default Consumption to protect existing installs). Currently set to Flex per the ticket.
2. **Host storage auth in Managed-Identity mode** moved from a shared-key connection string to identity-based (`AzureWebJobsStorage__accountName`). Intended (matches VNet/DACI), but it's a change for existing MI deployments. Local Authentication mode still uses the shared-key string.
3. **VNet integration mechanism** changed from a `networkConfig` resource to inline `virtualNetworkSubnetId`. Functionally equivalent; affects existing EP/Basic **private** deployments.
4. **`WEBSITE_RUN_FROM_PACKAGE`** is no longer set to `'0'` on non-Flex public plans — those use the ZipDeploy extension, and WRFP is only set for non-Flex private.

## Backward compatibility

The ElasticPremium / Basic / Consumption rows reproduce today's ASP specs exactly, and `alwaysOn` keeps its current rule (`= private`) for those plans. So an existing customer who **explicitly** picks their current plan should see no resource drift — to be confirmed by a what-if run. The open risk is the *default* (point 1 above).

## Known open items

- **Default-plan decision** (point 1) — needs Pavan.
- **Bicep mirror** — this change is ARM only; `bicep/azuredeploy-eventhubforwarder.bicep` still needs the same edits by hand.
- **No sandbox test yet** — see test plan.

## Test plan (required before merge)

- `az deployment group what-if` against an existing Flex-equivalent and against each existing plan to check for unexpected drift.
- Fresh deploy on each plan, public where valid:
  - FlexConsumption + public — FC1, code lands via deploy script, forwards logs.
  - ElasticPremium + public / + private.
  - Basic + public / + private.
  - Consumption + public.
  - FlexConsumption + private — deploy script runs in-subnet, reaches app via private endpoint, forwards logs.
  - Consumption + private — deployment must **fail** in ~1 min with the validator message.

_ARM template validates as JSON. Not yet deployed to Azure._
