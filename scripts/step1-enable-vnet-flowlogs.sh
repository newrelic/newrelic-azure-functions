#!/usr/bin/env bash
#
# Step 1: Enable VNet Flow Logs for an existing or new Virtual Network.
#
# This script:
#   1. Logs into Azure (if not already logged in)
#   2. Creates a resource group (if it doesn't exist)
#   3. Creates a VNet + subnet (or uses an existing one)
#   4. Creates a storage account for flow-log data
#   5. Enables VNet Flow Logs via Network Watcher
#
# Usage:
#   export SUFFIX="abc123"        # Optional: pin resource naming
#   export LOC="eastus"           # Optional: default region
#   export USE_EXISTING_VNET=true # Optional: skip VNet creation
#   export EXISTING_VNET_ID="/subscriptions/.../virtualNetworks/myVnet"
#   ./step1-enable-vnet-flowlogs.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.env
source "$SCRIPT_DIR/config.env"

echo "=============================================="
echo " Step 1: Enable VNet Flow Logs"
echo "=============================================="
echo "  Resource Group : $RG"
echo "  Location       : $LOC"
echo "  VNet           : $VNET ($VNET_CIDR)"
echo "  Storage        : $STORAGE"
echo "  Flow Log Name  : $FLOWLOG_NAME"
echo "  Suffix         : $SUFFIX"
echo "=============================================="
echo

# -----------------------------------------------------------------------------
# Login & subscription selection
# -----------------------------------------------------------------------------
login() {
  if ! az account show >/dev/null 2>&1; then
    echo "Not logged into Azure CLI. Initiating login..."
    az login
  fi

  echo "Current subscription:"
  az account show --query "{name:name, id:id}" -o table

  read -rp "Use this subscription? (y/n): " CONFIRM
  if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    az account list --output table
    read -rp "Enter subscription ID or name: " SUB
    az account set --subscription "$SUB"
    echo "Switched to subscription: $SUB"
  fi
}

# -----------------------------------------------------------------------------
# Resource group
# -----------------------------------------------------------------------------
create_resource_group() {
  echo "Creating resource group $RG in $LOC..."
  az group create --name "$RG" --location "$LOC" --output none
  echo "  ✓ Resource group ready."
}

# -----------------------------------------------------------------------------
# VNet + Subnet
# -----------------------------------------------------------------------------
create_vnet() {
  if [[ "${USE_EXISTING_VNET:-false}" == "true" ]]; then
    echo "Skipping VNet creation (USE_EXISTING_VNET=true)."
    return
  fi

  echo "Creating VNet $VNET..."
  az network vnet create \
    --resource-group "$RG" \
    --name "$VNET" \
    --address-prefixes "$VNET_CIDR" \
    --subnet-name "$SUBNET" \
    --subnet-prefixes "$SUBNET_CIDR" \
    --location "$LOC" \
    --output none
  echo "  ✓ VNet $VNET created with subnet $SUBNET."
}

# -----------------------------------------------------------------------------
# Storage account (flow-log destination)
# -----------------------------------------------------------------------------
create_storage() {
  echo "Creating storage account $STORAGE..."
  az storage account create \
    --name "$STORAGE" \
    --resource-group "$RG" \
    --location "$LOC" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --allow-blob-public-access false \
    --min-tls-version TLS1_2 \
    --output none
  echo "  ✓ Storage account $STORAGE ready."
}

# -----------------------------------------------------------------------------
# Enable VNet Flow Logs via Network Watcher
# -----------------------------------------------------------------------------
enable_flow_logs() {
  echo "Enabling Network Watcher for $LOC..."
  az network watcher configure --enabled true --locations "$LOC" --resource-group "$RG" --output none

  # Determine VNet resource ID
  local vnet_id
  if [[ "${USE_EXISTING_VNET:-false}" == "true" && -n "${EXISTING_VNET_ID:-}" ]]; then
    vnet_id="$EXISTING_VNET_ID"
  else
    vnet_id=$(az network vnet show -g "$RG" -n "$VNET" --query id -o tsv)
  fi

  local storage_id
  storage_id=$(az storage account show -n "$STORAGE" -g "$RG" --query id -o tsv)

  echo "Creating VNet Flow Log: $FLOWLOG_NAME..."
  az network watcher flow-log create \
    --location "$LOC" \
    --name "$FLOWLOG_NAME" \
    --resource-group NetworkWatcherRG \
    --vnet "$vnet_id" \
    --storage-account "$storage_id" \
    --enabled true \
    --retention 7 \
    --format JSON \
    --log-version 2 \
    --output none

  echo "  ✓ VNet Flow Logs enabled: $VNET -> $STORAGE/$FLOWLOG_CONTAINER"
}

# -----------------------------------------------------------------------------
# Verification
# -----------------------------------------------------------------------------
verify() {
  echo
  echo "--- Verification ---"
  echo "Resources in $RG:"
  az resource list -g "$RG" -o table

  echo
  echo "Flow log status:"
  az network watcher flow-log show \
    --location "$LOC" \
    --name "$FLOWLOG_NAME" \
    --resource-group NetworkWatcherRG \
    --query "{name:name, enabled:enabled, storageId:storageId, targetResourceId:targetResourceId}" \
    -o table 2>/dev/null || echo "  (flow log query returned no results yet)"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
  login
  create_resource_group
  create_vnet
  create_storage
  enable_flow_logs
  verify
  echo
  echo "=============================================="
  echo " Step 1 COMPLETE"
  echo "=============================================="
  echo "Flow logs will start writing to:"
  echo "  $STORAGE / $FLOWLOG_CONTAINER / ... / PT1H.json"
  echo
  echo "Next: Run step2-deploy-arm-template.sh to create the ingestion pipeline."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
