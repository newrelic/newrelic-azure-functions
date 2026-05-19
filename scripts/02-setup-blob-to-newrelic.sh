#!/usr/bin/env bash
#
# Script 2 of 2: Stand up the ingestion pipeline that forwards VNet Flow Log
# blobs to New Relic Logs.
#
# Pipeline:
#   Storage (flow log blob appended)
#     -> Event Grid subscription (BlobCreated event, filtered to flow log container)
#     -> Event Hub (queue; a small relay Function sets partitionKey = event.subject)
#     -> Event Hub-triggered consumer Function
#     -> Azure Table Storage `cursors` (per-blob block-count bookmark)
#     -> delta block download from Blob
#     -> POST to New Relic Logs
#
# Prereqs:
#   - Script 1 has been run (RG + VNet + Storage + flow logs exist).
#   - NR_LICENSE_KEY is exported in the current shell.
#   - SUFFIX matches the value used when running script 1 (pin it by exporting
#     before running either script).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=config.env
source "$SCRIPT_DIR/config.env"

: "${NR_LICENSE_KEY:?Set NR_LICENSE_KEY in your shell before running}"

echo "Script 2 config:"
echo "  RG=$RG  LOC=$LOC  SUFFIX=$SUFFIX"
echo "  STORAGE=$STORAGE  EHNS=$EHNS/$EH  FUNCAPP=$FUNCAPP"
echo

# -----------------------------------------------------------------------------
# Sanity check: verify script 1 ran successfully.
# -----------------------------------------------------------------------------
verify_prereqs() {
  if ! az account show >/dev/null 2>&1; then
    az login
  fi
  if ! az group show -n "$RG" >/dev/null 2>&1; then
    echo "Resource group $RG not found. Run script 1 first." >&2
    exit 1
  fi
  if ! az storage account show -n "$STORAGE" -g "$RG" >/dev/null 2>&1; then
    echo "Storage account $STORAGE not found. Run script 1 first." >&2
    exit 1
  fi
  echo "Prereqs OK."
}

# -----------------------------------------------------------------------------
# 1. Event Hub (namespace + hub + consumer group)
# -----------------------------------------------------------------------------
create_event_hub() {
  az eventhubs namespace create \
    --name "$EHNS" --resource-group "$RG" --location "$LOC" --sku Standard >/dev/null

  az eventhubs eventhub create \
    --name "$EH" --resource-group "$RG" --namespace-name "$EHNS" \
    --partition-count 8 --retention-time-in-hours 24 --cleanup-policy Delete >/dev/null

  az eventhubs eventhub consumer-group create \
    --name "$EH_CG" --eventhub-name "$EH" \
    --namespace-name "$EHNS" --resource-group "$RG" >/dev/null
  echo "Event Hub $EHNS/$EH ready (consumer group $EH_CG)."
}

# -----------------------------------------------------------------------------
# 2. Function App (Linux, Node 22, Functions v4)
# -----------------------------------------------------------------------------
create_function_app() {
  az functionapp create \
    --name "$FUNCAPP" --resource-group "$RG" \
    --consumption-plan-location "$LOC" \
    --storage-account "$STORAGE" \
    --runtime node --runtime-version 22 --functions-version 4 --os-type Linux >/dev/null
  echo "Function App $FUNCAPP ready."
}

# -----------------------------------------------------------------------------
# 3. Event Grid: storage-account BlobCreated -> Event Hub
#    Filtered to the VNet flow-log container so unrelated blobs don't fan in.
# -----------------------------------------------------------------------------
create_event_grid_subscription() {
  local storage_id eh_id
  storage_id=$(az storage account show -n "$STORAGE" -g "$RG" --query id -o tsv)
  eh_id=$(az eventhubs eventhub show -n "$EH" --namespace-name "$EHNS" -g "$RG" --query id -o tsv)

  az eventgrid event-subscription create \
    --name "$EVG_SUB" \
    --source-resource-id "$storage_id" \
    --endpoint "$eh_id" --endpoint-type eventhub \
    --included-event-types Microsoft.Storage.BlobCreated \
    --subject-begins-with "/blobServices/default/containers/$FLOWLOG_CONTAINER/" >/dev/null
  echo "Event Grid subscription $EVG_SUB created."
}

# -----------------------------------------------------------------------------
# 4. Function App settings (deployed env vars)
# -----------------------------------------------------------------------------
configure_function_app_settings() {
  local storage_cs eh_cs
  storage_cs=$(az storage account show-connection-string -n "$STORAGE" -g "$RG" --query connectionString -o tsv)
  eh_cs=$(az eventhubs namespace authorization-rule keys list \
    -g "$RG" --namespace-name "$EHNS" --name RootManageSharedAccessKey \
    --query primaryConnectionString -o tsv)

  az functionapp config appsettings set --name "$FUNCAPP" --resource-group "$RG" --settings \
    VNETFLOW_RELAY_ENABLED=true \
    VNETFLOWLOGS_FORWARDER_ENABLED=true \
    SOURCE_STORAGE_CONNECTION="$storage_cs" \
    CURSOR_STORAGE_CONNECTION="$storage_cs" \
    CURSOR_TABLE_NAME="$TABLE" \
    EVENTHUB_CONSUMER_CONNECTION="$eh_cs" \
    EVENTHUB_NAME="$EH" \
    EVENTHUB_CONSUMER_GROUP="$EH_CG" \
    EVENTHUB_BATCH_SIZE=10 \
    NR_LICENSE_KEY="$NR_LICENSE_KEY" \
    NR_ENDPOINT="$NR_ENDPOINT" >/dev/null
  echo "Function App settings written."
}

# -----------------------------------------------------------------------------
# 5. local.settings.json for `func start` on your Mac (NOT committed)
# -----------------------------------------------------------------------------
emit_local_settings() {
  local storage_cs eh_cs
  storage_cs=$(az storage account show-connection-string -n "$STORAGE" -g "$RG" --query connectionString -o tsv)
  eh_cs=$(az eventhubs namespace authorization-rule keys list \
    -g "$RG" --namespace-name "$EHNS" --name RootManageSharedAccessKey \
    --query primaryConnectionString -o tsv)

  cat > "$REPO_ROOT/local.settings.json" <<EOF
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "UseDevelopmentStorage=true",
    "FUNCTIONS_WORKER_RUNTIME": "node",
    "FUNCTIONS_EXTENSION_VERSION": "~4",
    "VNETFLOW_RELAY_ENABLED": "true",
    "VNETFLOWLOGS_FORWARDER_ENABLED": "true",
    "SOURCE_STORAGE_CONNECTION": "$storage_cs",
    "CURSOR_STORAGE_CONNECTION": "$storage_cs",
    "CURSOR_TABLE_NAME": "$TABLE",
    "EVENTHUB_CONSUMER_CONNECTION": "$eh_cs",
    "EVENTHUB_NAME": "$EH",
    "EVENTHUB_CONSUMER_GROUP": "$EH_CG",
    "EVENTHUB_BATCH_SIZE": "10",
    "NR_LICENSE_KEY": "$NR_LICENSE_KEY",
    "NR_ENDPOINT": "$NR_ENDPOINT"
  }
}
EOF
  echo "Wrote $REPO_ROOT/local.settings.json"
  grep -q "^local.settings.json$" "$REPO_ROOT/.gitignore" \
    || echo "local.settings.json" >> "$REPO_ROOT/.gitignore"
}

# -----------------------------------------------------------------------------
# 6. npm deps for the relay + consumer Functions
# -----------------------------------------------------------------------------
install_npm_deps() {
  (
    cd "$REPO_ROOT"
    npm install \
      @azure/data-tables \
      @azure/storage-blob \
      @azure/event-hubs \
      @azure/identity
  )
}

# -----------------------------------------------------------------------------
# 7. Verify
# -----------------------------------------------------------------------------
verify() {
  echo "--- resources in $RG ---"
  az resource list -g "$RG" -o table
  echo "--- event grid subs on storage ---"
  local storage_id
  storage_id=$(az storage account show -n "$STORAGE" -g "$RG" --query id -o tsv)
  az eventgrid event-subscription list --source-resource-id "$storage_id" -o table
}

main() {
  verify_prereqs
  create_event_hub
  create_function_app
  create_event_grid_subscription
  configure_function_app_settings
  install_npm_deps
  emit_local_settings
  verify
  cat <<DONE

Script 2 complete. Ingestion pipeline is provisioned.

Next steps:
  1. Run locally with \`func start\` (Azurite must also be running).
  2. Deploy with \`func azure functionapp publish $FUNCAPP\`.

DONE
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
