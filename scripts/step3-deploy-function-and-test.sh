#!/usr/bin/env bash
#
# Step 3: Deploy the Azure Function code and verify logs in New Relic.
#
# This script:
#   1. Packages the VNetFlowForwarder function as a zip
#   2. Deploys it to the Function App created by the ARM template
#   3. Verifies the function is running
#   4. Generates test traffic (optional)
#   5. Queries New Relic to confirm flow logs arrive
#
# Prerequisites:
#   - Steps 1 & 2 completed (flow logs enabled, ARM template deployed)
#   - NR_LICENSE_KEY exported
#   - NR_ACCOUNT_ID exported (for NRQL verification queries)
#   - Azure Functions Core Tools installed (`npm i -g azure-functions-core-tools@4`)
#
# Usage:
#   export NR_LICENSE_KEY="your-key-here"
#   export NR_ACCOUNT_ID="1234567"
#   export SUFFIX="abc123"     # Must match Steps 1 & 2
#   ./step3-deploy-function-and-test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=config.env
source "$SCRIPT_DIR/config.env"

: "${NR_LICENSE_KEY:?ERROR: Set NR_LICENSE_KEY in your shell before running}"

# Load ARM template outputs if available
if [[ -f "$SCRIPT_DIR/.arm-outputs.env" ]]; then
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/.arm-outputs.env"
fi

# Fall back to discovering the function app name
FUNC_APP_NAME="${FUNC_APP_NAME:-$FUNCAPP}"

echo "=============================================="
echo " Step 3: Deploy Function & Test"
echo "=============================================="
echo "  Resource Group : $RG"
echo "  Function App   : $FUNC_APP_NAME"
echo "  NR Endpoint    : $NR_ENDPOINT"
echo "  NR Account ID  : ${NR_ACCOUNT_ID:-<not set — skip verification>}"
echo "  Suffix         : $SUFFIX"
echo "=============================================="
echo

# -----------------------------------------------------------------------------
# Pre-flight checks
# -----------------------------------------------------------------------------
preflight() {
  if ! az account show >/dev/null 2>&1; then
    echo "Not logged into Azure CLI. Initiating login..."
    az login
  fi

  if ! az group show -n "$RG" >/dev/null 2>&1; then
    echo "ERROR: Resource group $RG not found. Run steps 1 and 2 first." >&2
    exit 1
  fi

  # Check if function app exists (will be created later if not)
  if az functionapp show -n "$FUNC_APP_NAME" -g "$RG" >/dev/null 2>&1; then
    echo "  ✓ Function App $FUNC_APP_NAME found."
  else
    echo "  ℹ Function App $FUNC_APP_NAME not found — will create it."
  fi

  # Check for func CLI (optional — we prefer zip deploy)
  if command -v func >/dev/null 2>&1; then
    echo "  ✓ Azure Functions Core Tools detected."
    USE_FUNC_CLI=true
  else
    echo "  ℹ Azure Functions Core Tools not found. Using zip deploy via az CLI."
    USE_FUNC_CLI=false
  fi

  echo "  ✓ Pre-flight checks passed."
  echo
}

# -----------------------------------------------------------------------------
# Create Function App (if ARM template skipped it due to quota)
# -----------------------------------------------------------------------------
create_function_app_if_needed() {
  if az functionapp show -n "$FUNC_APP_NAME" -g "$RG" >/dev/null 2>&1; then
    echo "  Function App $FUNC_APP_NAME already exists. Skipping creation."
    return
  fi

  echo "Creating Function App $FUNC_APP_NAME via CLI..."

  # Get the function storage account name from ARM outputs
  local func_storage
  func_storage=$(az storage account list -g "$RG" \
    --query "[?starts_with(name,'nrvnetfunc')].name" -o tsv 2>/dev/null || echo "")

  if [[ -z "$func_storage" ]]; then
    echo "  No function storage account found. Using source storage: $STORAGE"
    func_storage="$STORAGE"
  fi

  az functionapp create \
    --name "$FUNC_APP_NAME" \
    --resource-group "$RG" \
    --consumption-plan-location "$LOC" \
    --storage-account "$func_storage" \
    --runtime node \
    --runtime-version 22 \
    --functions-version 4 \
    --os-type Linux \
    --output none

  echo "  ✓ Function App $FUNC_APP_NAME created."

  # Configure app settings
  echo "  Configuring app settings..."
  local source_cs cursor_cs eh_cs cursor_storage
  source_cs=$(az storage account show-connection-string -n "$STORAGE" -g "$RG" --query connectionString -o tsv)

  cursor_storage=$(az storage account list -g "$RG" \
    --query "[?starts_with(name,'nrvnetcur')].name" -o tsv 2>/dev/null || echo "")
  if [[ -z "$cursor_storage" ]]; then
    cursor_storage="$STORAGE"
  fi
  cursor_cs=$(az storage account show-connection-string -n "$cursor_storage" -g "$RG" --query connectionString -o tsv)

  local eh_ns
  eh_ns=$(az eventhubs namespace list -g "$RG" --query "[0].name" -o tsv)
  eh_cs=$(az eventhubs namespace authorization-rule keys list \
    -g "$RG" --namespace-name "$eh_ns" --name nrvnetflowlogs-auth-rule \
    --query primaryConnectionString -o tsv 2>/dev/null || \
    az eventhubs namespace authorization-rule keys list \
    -g "$RG" --namespace-name "$eh_ns" --name RootManageSharedAccessKey \
    --query primaryConnectionString -o tsv)

  az functionapp config appsettings set --name "$FUNC_APP_NAME" --resource-group "$RG" --settings \
    VNETFLOW_RELAY_ENABLED=true \
    VNETFLOWLOGS_FORWARDER_ENABLED=true \
    SOURCE_STORAGE_CONNECTION="$source_cs" \
    CURSOR_STORAGE_CONNECTION="$cursor_cs" \
    CURSOR_TABLE_NAME="vnetflowlogcursors" \
    EVENTHUB_CONSUMER_CONNECTION="$eh_cs" \
    EVENTHUB_NAME="nrvnetflowlogs" \
    EVENTHUB_CONSUMER_GROUP="nrvnetflowlogs" \
    NR_LICENSE_KEY="$NR_LICENSE_KEY" \
    NR_ENDPOINT="$NR_ENDPOINT" \
    --output none

  echo "  ✓ App settings configured."
  echo
}

# -----------------------------------------------------------------------------
# Package the function
# -----------------------------------------------------------------------------
package_function() {
  echo "Packaging VNetFlowForwarder..."
  cd "$REPO_ROOT"

  # Install production dependencies only
  npm ci --omit=dev --quiet 2>/dev/null

  # Create deployment zip
  local zip_file="$REPO_ROOT/VNetFlowForwarder.zip"
  rm -f "$zip_file"
  zip -qr "$zip_file" \
    VNetFlowForwarder/ \
    host.json \
    package.json \
    node_modules/

  echo "  ✓ Package created: VNetFlowForwarder.zip ($(du -h "$zip_file" | cut -f1))"
  echo
}

# -----------------------------------------------------------------------------
# Deploy to Azure
# -----------------------------------------------------------------------------
deploy_function() {
  echo "Deploying to $FUNC_APP_NAME..."

  if [[ "$USE_FUNC_CLI" == "true" ]]; then
    # Use func CLI (provides better progress output)
    cd "$REPO_ROOT"
    func azure functionapp publish "$FUNC_APP_NAME" --javascript
  else
    # Use az CLI zip deploy
    az functionapp deployment source config-zip \
      --name "$FUNC_APP_NAME" \
      --resource-group "$RG" \
      --src "$REPO_ROOT/VNetFlowForwarder.zip" \
      --output none
  fi

  echo "  ✓ Function code deployed."
  echo
}

# -----------------------------------------------------------------------------
# Verify function is running
# -----------------------------------------------------------------------------
verify_function() {
  echo "Verifying function app status..."

  local state
  state=$(az functionapp show -n "$FUNC_APP_NAME" -g "$RG" --query state -o tsv)
  echo "  Function App state: $state"

  if [[ "$state" != "Running" ]]; then
    echo "  WARNING: Function App is not in 'Running' state." >&2
    echo "  Attempting restart..."
    az functionapp restart -n "$FUNC_APP_NAME" -g "$RG" --output none
    sleep 10
    state=$(az functionapp show -n "$FUNC_APP_NAME" -g "$RG" --query state -o tsv)
    echo "  State after restart: $state"
  fi

  echo
  echo "  Listing registered functions:"
  az functionapp function list -n "$FUNC_APP_NAME" -g "$RG" \
    --query "[].{name:name, isDisabled:isDisabled}" -o table 2>/dev/null \
    || echo "  (functions not yet visible — may take 1-2 minutes after deploy)"
  echo
}

# -----------------------------------------------------------------------------
# Generate test traffic (optional — creates a small VM to produce flows)
# -----------------------------------------------------------------------------
generate_test_traffic() {
  read -rp "Generate test traffic with a temporary VM? (y/n): " GEN_TRAFFIC
  if [[ "$GEN_TRAFFIC" != "y" && "$GEN_TRAFFIC" != "Y" ]]; then
    echo "Skipping traffic generation. Flow logs from existing network activity"
    echo "will be forwarded once PT1H.json blobs are written (up to 1 hour)."
    return
  fi

  echo "Creating a temporary test VM to generate network traffic..."
  local vm_name="vm-flowtest-${SUFFIX}"

  az vm create \
    --resource-group "$RG" \
    --name "$vm_name" \
    --image Ubuntu2204 \
    --size Standard_B1s \
    --vnet-name "$VNET" \
    --subnet "$SUBNET" \
    --admin-username azureuser \
    --generate-ssh-keys \
    --public-ip-address "" \
    --output none 2>/dev/null

  echo "  ✓ Test VM $vm_name created."
  echo "  Traffic will appear in flow logs within 1-10 minutes."
  echo
  echo "  (Clean up later with: az vm delete -g $RG -n $vm_name --yes)"
}

# -----------------------------------------------------------------------------
# Check New Relic for flow logs
# -----------------------------------------------------------------------------
check_newrelic() {
  if [[ -z "${NR_ACCOUNT_ID:-}" ]]; then
    echo "NR_ACCOUNT_ID not set — skipping New Relic verification."
    echo "You can manually verify with this NRQL query in New Relic:"
    echo
    echo "  FROM Log SELECT count(*)"
    echo "  WHERE azure.category = 'FlowLogFlowEvent'"
    echo "  SINCE 1 hour ago"
    echo
    return
  fi

  # Determine the correct API region
  local nrql_endpoint="https://insights-api.newrelic.com/v1/accounts/${NR_ACCOUNT_ID}/query"
  if [[ "$NR_ENDPOINT" == *"eu.newrelic"* ]]; then
    nrql_endpoint="https://insights-api.eu.newrelic.com/v1/accounts/${NR_ACCOUNT_ID}/query"
  fi

  echo "Querying New Relic for VNet flow logs..."
  echo "  (Flow logs can take 5-15 minutes after first traffic to appear)"
  echo

  local nrql="SELECT count(*) FROM Log WHERE azure.category = 'FlowLogFlowEvent' SINCE 30 minutes ago"

  local max_attempts=6
  local wait_seconds=30

  for attempt in $(seq 1 $max_attempts); do
    echo "  Attempt $attempt/$max_attempts..."
    local response
    response=$(curl -s -X GET "$nrql_endpoint" \
      -H "Accept: application/json" \
      -H "X-Query-Key: $NR_LICENSE_KEY" \
      --data-urlencode "nrql=$nrql" 2>/dev/null || echo "")

    if echo "$response" | grep -q '"results"'; then
      local count
      count=$(echo "$response" | grep -o '"count":[0-9]*' | head -1 | cut -d: -f2)
      if [[ -n "$count" && "$count" -gt 0 ]]; then
        echo
        echo "  ✓ SUCCESS: Found $count flow log records in New Relic!"
        echo
        echo "  Explore with:"
        echo "    FROM Log SELECT *"
        echo "    WHERE azure.category = 'FlowLogFlowEvent'"
        echo "    SINCE 1 hour ago LIMIT 100"
        return 0
      fi
    fi

    if [[ $attempt -lt $max_attempts ]]; then
      echo "    No records yet. Waiting ${wait_seconds}s..."
      sleep "$wait_seconds"
    fi
  done

  echo
  echo "  ⚠ No flow log records found in New Relic yet."
  echo "  This is normal if:"
  echo "    - You just enabled flow logs (first PT1H.json takes up to 1 hour)"
  echo "    - The function was just deployed (cold start + Event Grid propagation)"
  echo
  echo "  Check back in 15-60 minutes with:"
  echo "    FROM Log SELECT * WHERE azure.category = 'FlowLogFlowEvent' SINCE 2 hours ago"
}

# -----------------------------------------------------------------------------
# Show function logs
# -----------------------------------------------------------------------------
show_function_logs() {
  echo "Recent function app logs:"
  az functionapp log tail -n "$FUNC_APP_NAME" -g "$RG" --timeout 10 2>/dev/null \
    || echo "  (log streaming not available — check Application Insights in the portal)"
  echo
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
  preflight
  create_function_app_if_needed
  package_function
  deploy_function
  verify_function
  generate_test_traffic
  echo
  echo "--- Checking New Relic for flow log data ---"
  check_newrelic
  echo
  echo "=============================================="
  echo " Step 3 COMPLETE"
  echo "=============================================="
  echo
  echo "Summary:"
  echo "  - Function deployed to: $FUNC_APP_NAME"
  echo "  - Pipeline: Storage -> Event Grid -> Event Hub -> Function -> New Relic"
  echo
  echo "Useful commands:"
  echo "  # View function logs"
  echo "  az functionapp log tail -n $FUNC_APP_NAME -g $RG"
  echo
  echo "  # Check function status"
  echo "  az functionapp show -n $FUNC_APP_NAME -g $RG --query state -o tsv"
  echo
  echo "  # Redeploy after code changes"
  echo "  func azure functionapp publish $FUNC_APP_NAME --javascript"
  echo
  echo "  # NRQL query"
  echo "  FROM Log SELECT * WHERE azure.category = 'FlowLogFlowEvent' SINCE 1 hour ago"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
