#!/bin/bash

###############################################################################
# VNet Flow Logs - Complete Setup Deployment (Prerequisites + Infrastructure)
###############################################################################
# This script deploys EVERYTHING from scratch:
# - VNet + Subnet + NSG
# - Network Watcher + Flow Logs
# - Source Storage (for PT1H.json files)
# - Event Grid + Event Hub + Function App
# - All connections and permissions
#
# Usage:
#   ./deploy-complete.sh <resource-group-name> [location]
#
# Example:
#   ./deploy-complete.sh bpavan-vnet-logs-arm canadacentral
###############################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check Azure CLI
if ! command -v az &> /dev/null; then
    print_error "Azure CLI not installed. Install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check login
if ! az account show &> /dev/null; then
    print_error "Not logged in. Run 'az login' first."
    exit 1
fi

# Get parameters
RESOURCE_GROUP=$1
LOCATION=${2:-canadacentral}

if [ -z "$RESOURCE_GROUP" ]; then
    print_error "Usage: $0 <resource-group-name> [location]"
    print_info "Example: $0 bpavan-vnet-logs-arm canadacentral"
    exit 1
fi

# Ensure resource group has bpavan- prefix
if [[ ! "$RESOURCE_GROUP" =~ ^bpavan- ]]; then
    print_warning "Resource group name should start with 'bpavan-' for easy identification"
    print_warning "Current: $RESOURCE_GROUP"
    print_warning "Suggested: bpavan-$RESOURCE_GROUP"
    echo ""
    echo -n "Continue anyway? (y/n) "
    read -r RESPONSE
    if [[ ! $RESPONSE =~ ^[Yy]$ ]]; then
        print_info "Cancelled. Please use a resource group name starting with 'bpavan-'"
        exit 0
    fi
fi

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TEMPLATE_FILE="$SCRIPT_DIR/azuredeploy-vnetflowlogs-complete.json"
PARAMETERS_FILE="$SCRIPT_DIR/azuredeploy-vnetflowlogs-complete.parameters.json"

# Validate files
if [ ! -f "$TEMPLATE_FILE" ]; then
    print_error "Template file not found: $TEMPLATE_FILE"
    exit 1
fi

if [ ! -f "$PARAMETERS_FILE" ]; then
    print_error "Parameters file not found: $PARAMETERS_FILE"
    exit 1
fi

print_info "====================================================================="
print_info "VNet Flow Logs - Complete Setup Deployment"
print_info "====================================================================="
print_info "Resource Group: $RESOURCE_GROUP"
print_info "Location: $LOCATION"
print_info "Template: Complete (VNet + Flow Logs + Forwarder)"
print_info "Idempotent: ✓ Safe to re-run (updates existing resources)"
print_info "====================================================================="
echo ""

SUBSCRIPTION=$(az account show --query name -o tsv)
print_info "Azure Subscription: $SUBSCRIPTION"
echo ""

echo -n "Deploy complete setup? (y/n) "
read -r RESPONSE
if [[ ! $RESPONSE =~ ^[Yy]$ ]]; then
    print_warning "Cancelled."
    exit 0
fi

echo ""
print_info "Step 1: Creating resource group..."
if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
    print_warning "Resource group exists. Using existing."
else
    az group create --name "$RESOURCE_GROUP" --location "$LOCATION"
    print_success "Resource group created: $RESOURCE_GROUP"
fi

echo ""
print_info "Step 2: Validating template..."
VALIDATION_OUTPUT=$(az deployment group validate \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$TEMPLATE_FILE" \
    --parameters "@$PARAMETERS_FILE" \
    2>&1)

if [ $? -eq 0 ]; then
    print_success "Validation passed!"
else
    print_error "Validation failed:"
    echo "$VALIDATION_OUTPUT"
    exit 1
fi

echo ""
print_info "Step 3: Running what-if analysis..."
print_warning "This shows what resources will be created..."
az deployment group what-if \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$TEMPLATE_FILE" \
    --parameters "@$PARAMETERS_FILE"

echo ""
echo -n "Review above. Continue? (y/n) "
read -r RESPONSE
if [[ ! $RESPONSE =~ ^[Yy]$ ]]; then
    print_warning "Cancelled."
    exit 0
fi

echo ""
print_info "Step 4: Deploying complete setup..."
print_warning "This will take 10-15 minutes..."
print_info ""
print_info "Creating:"
print_info "  ✓ Virtual Network + Subnet + NSG"
print_info "  ✓ Network Watcher + Flow Logs"
print_info "  ✓ Source Storage Account"
print_info "  ✓ Event Grid System Topic"
print_info "  ✓ Event Hub Namespace + Event Hub"
print_info "  ✓ Function App + Internal Storage"
print_info "  ✓ All connections and permissions"
echo ""

DEPLOYMENT_NAME="vnetflowlogs-complete-$(date +%Y%m%d-%H%M%S)"

DEPLOYMENT_OUTPUT=$(az deployment group create \
    --name "$DEPLOYMENT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$TEMPLATE_FILE" \
    --parameters "@$PARAMETERS_FILE" \
    --output json)

if [ $? -eq 0 ]; then
    print_success "Deployment completed!"

    # Extract outputs
    VNET_NAME=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.vnetName.value')
    NSG_NAME=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.nsgName.value')
    SOURCE_STORAGE=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.sourceStorageAccountName.value')
    FUNCTION_APP_NAME=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.functionAppName.value')
    EVENT_HUB_NAME=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.eventHubName.value')
    FLOW_LOGS_NAME=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.flowLogsName.value')

    echo ""
    print_info "====================================================================="
    print_info "Deployment Outputs"
    print_info "====================================================================="
    print_info "Virtual Network: $VNET_NAME"
    print_info "Network Security Group: $NSG_NAME"
    print_info "Flow Logs: $FLOW_LOGS_NAME"
    print_info "Source Storage: $SOURCE_STORAGE (PT1H.json files will be written here)"
    print_info "Event Hub: $EVENT_HUB_NAME"
    print_info "Function App: $FUNCTION_APP_NAME"
    print_info "====================================================================="

    echo ""
    print_success "====================================================================="
    print_success "Setup Complete!"
    print_success "====================================================================="
    print_success ""
    print_success "All resources created and connected!"
    print_success "Storage permissions automatically granted to Function App."
    print_success ""
    print_warning "NEXT STEP: Deploy Function Code"
    print_warning ""
    echo -e "${YELLOW}  cd /Users/bpavan/repos/logint/nr/newrelic-azure-functions
  npm run package:logforwarder
  az functionapp deployment source config-zip \\
    --resource-group $RESOURCE_GROUP \\
    --name $FUNCTION_APP_NAME \\
    --src LogForwarder.zip
  az functionapp restart --resource-group $RESOURCE_GROUP --name $FUNCTION_APP_NAME${NC}"
    print_warning ""
    print_warning "====================================================================="

    echo ""
    print_info "⏰ IMPORTANT: Flow logs take 5-10 minutes to start generating"
    print_info "After deploying code, wait ~10 minutes before checking logs."
    print_info ""
    print_info "To monitor: az webapp log tail --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP"

else
    print_error "Deployment failed."
    exit 1
fi