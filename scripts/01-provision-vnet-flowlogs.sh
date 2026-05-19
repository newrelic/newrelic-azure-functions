#!/usr/bin/env bash
#
# Script 1 of 2: Provision the VNet and enable VNet Flow Logs writing to a
# Storage account. This is pure networking + telemetry capture -- nothing
# here touches New Relic or the ingestion pipeline.
#
# After this completes, VNet Flow Logs will start appending data every minute
# to blobs under:
#   <STORAGE>/insights-logs-flowlogflowevent/.../PT1H.json
#
# Run script 2 (02-setup-blob-to-newrelic.sh) next to stand up the ingestion
# pipeline that forwards that data to New Relic.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.env
source "$SCRIPT_DIR/config.env"

echo "Script 1 config:"
echo "  RG=$RG  LOC=$LOC  SUFFIX=$SUFFIX"
echo "  VNET=$VNET ($VNET_CIDR)  SUBNET=$SUBNET ($SUBNET_CIDR)"
echo "  STORAGE=$STORAGE  FLOWLOG_NAME=$FLOWLOG_NAME"
echo

# -----------------------------------------------------------------------------
# 1. Auth + resource group
# -----------------------------------------------------------------------------
az_login() {
  if ! az account show >/dev/null 2>&1; then
    az login
  fi
  az account list --output table
  read -rp "Subscription ID or name to use: " SUB
  az account set --subscription "$SUB"
  az group create --name "$RG" --location "$LOC" >/dev/null
  echo "Resource group $RG ready."
}

# -----------------------------------------------------------------------------
# 2. VNet + subnet
# -----------------------------------------------------------------------------
create_vnet() {
  az network vnet create \
    --resource-group "$RG" \
    --name "$VNET" \
    --address-prefixes "$VNET_CIDR" \
    --subnet-name "$SUBNET" \
    --subnet-prefixes "$SUBNET_CIDR" \
    --location "$LOC" >/dev/null
  echo "VNet $VNET created with subnet $SUBNET."
}

# -----------------------------------------------------------------------------
# 3. Storage account (flow log destination + cursor Table)
#    Script 2 reuses this same storage account; don't recreate it there.
# -----------------------------------------------------------------------------
create_storage() {
  az storage account create \
    --name "$STORAGE" --resource-group "$RG" --location "$LOC" \
    --sku Standard_LRS --kind StorageV2 --allow-blob-public-access false >/dev/null

  # Pre-create the cursor table now so script 2 / local dev can rely on it.
  az storage table create \
    --name "$TABLE" --account-name "$STORAGE" --auth-mode login >/dev/null
  echo "Storage $STORAGE + table $TABLE ready."
}

# -----------------------------------------------------------------------------
# 4. VNet Flow Logs
#    Network Watcher is enabled per-region (idempotent). Flow logs live in the
#    auto-managed NetworkWatcherRG resource group.
# -----------------------------------------------------------------------------
enable_flow_logs() {
  az network watcher configure --enabled true --locations "$LOC" >/dev/null

  local vnet_id storage_id
  vnet_id=$(az network vnet show -g "$RG" -n "$VNET" --query id -o tsv)
  storage_id=$(az storage account show -n "$STORAGE" -g "$RG" --query id -o tsv)

  az network watcher flow-log create \
    --location "$LOC" \
    --name "$FLOWLOG_NAME" \
    --resource-group NetworkWatcherRG \
    --vnet "$vnet_id" \
    --storage-account "$storage_id" \
    --enabled true \
    --retention 7 \
    --format JSON --log-version 2 >/dev/null

  echo "VNet Flow Logs enabled on $VNET -> $STORAGE/$FLOWLOG_CONTAINER"
}

# -----------------------------------------------------------------------------
# 5. Verify
# -----------------------------------------------------------------------------
verify() {
  echo "--- resource group contents ---"
  az resource list -g "$RG" -o table
  echo "--- flow log status ---"
  az network watcher flow-log show \
    --location "$LOC" --name "$FLOWLOG_NAME" \
    --resource-group NetworkWatcherRG -o table
}

main() {
  az_login
  create_vnet
  create_storage
  enable_flow_logs
  verify
  cat <<DONE

Script 1 complete.

Flow logs will appear in:
  az storage blob list \\
    --account-name $STORAGE \\
    --container-name $FLOWLOG_CONTAINER \\
    --auth-mode login -o table

Note: flow logs only capture real traffic. If the subnet is empty, no blobs
will be created. Deploy a VM/NAT gateway into $SUBNET to generate data.

Next: run ./scripts/02-setup-blob-to-newrelic.sh with NR_LICENSE_KEY exported.
DONE
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
