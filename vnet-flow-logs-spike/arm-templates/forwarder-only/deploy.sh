#!/bin/bash

###############################################################################
# VNet Flow Logs Forwarder - ARM Template Deployment Script (Azure CLI)
###############################################################################
# This script deploys the VNet Flow Logs forwarder infrastructure using
# the ARM template and parameters file.
#
# Usage:
#   ./deploy.sh <resource-group-name> [location]
#
# Example:
#   ./deploy.sh bpavan-vnet-logs-arm canadacentral
###############################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
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

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    print_error "Azure CLI is not installed. Please install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check if logged in to Azure
if ! az account show &> /dev/null; then
    print_error "Not logged in to Azure. Please run 'az login' first."
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

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TEMPLATE_FILE="$SCRIPT_DIR/azuredeploy-vnetflowlogsforwarder.json"
PARAMETERS_FILE="$SCRIPT_DIR/azuredeploy-vnetflowlogsforwarder.parameters.json"

# Validate files exist
if [ ! -f "$TEMPLATE_FILE" ]; then
    print_error "Template file not found: $TEMPLATE_FILE"
    exit 1
fi

if [ ! -f "$PARAMETERS_FILE" ]; then
    print_error "Parameters file not found: $PARAMETERS_FILE"
    exit 1
fi

print_info "====================================================================="
print_info "VNet Flow Logs Forwarder - ARM Template Deployment"
print_info "====================================================================="
print_info "Resource Group: $RESOURCE_GROUP"
print_info "Location: $LOCATION"
print_info "Template: $TEMPLATE_FILE"
print_info "Parameters: $PARAMETERS_FILE"
print_info "====================================================================="
echo ""

# Get current subscription
SUBSCRIPTION=$(az account show --query name -o tsv)
print_info "Current Azure Subscription: $SUBSCRIPTION"
echo ""

read -p "Do you want to proceed with the deployment? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Deployment cancelled by user."
    exit 0
fi

echo ""
print_info "Step 1: Creating resource group (if it doesn't exist)..."
if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
    print_warning "Resource group '$RESOURCE_GROUP' already exists. Using existing resource group."
else
    az group create --name "$RESOURCE_GROUP" --location "$LOCATION"
    print_success "Resource group created: $RESOURCE_GROUP"
fi

echo ""
print_info "Step 2: Validating ARM template..."
VALIDATION_OUTPUT=$(az deployment group validate \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$TEMPLATE_FILE" \
    --parameters "@$PARAMETERS_FILE" \
    2>&1)

if [ $? -eq 0 ]; then
    print_success "Template validation passed!"
else
    print_error "Template validation failed:"
    echo "$VALIDATION_OUTPUT"
    exit 1
fi

echo ""
print_info "Step 3: Running 'what-if' analysis..."
print_warning "This shows what resources will be created/modified..."
az deployment group what-if \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$TEMPLATE_FILE" \
    --parameters "@$PARAMETERS_FILE"

echo ""
read -p "Review the what-if output above. Continue with deployment? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Deployment cancelled by user."
    exit 0
fi

echo ""
print_info "Step 4: Deploying ARM template..."
print_warning "This may take 5-10 minutes..."
DEPLOYMENT_NAME="vnetflowlogs-$(date +%Y%m%d-%H%M%S)"

DEPLOYMENT_OUTPUT=$(az deployment group create \
    --name "$DEPLOYMENT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$TEMPLATE_FILE" \
    --parameters "@$PARAMETERS_FILE" \
    --output json)

if [ $? -eq 0 ]; then
    print_success "Deployment completed successfully!"

    # Extract outputs
    FUNCTION_APP_NAME=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.functionAppName.value')
    EVENT_HUB_NAME=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.eventHubName.value')
    STORAGE_ACCOUNT_NAME=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.storageAccountName.value')

    echo ""
    print_info "====================================================================="
    print_info "Deployment Outputs"
    print_info "====================================================================="
    print_info "Function App Name: $FUNCTION_APP_NAME"
    print_info "Event Hub Name: $EVENT_HUB_NAME"
    print_info "Storage Account Name: $STORAGE_ACCOUNT_NAME"
    print_info "====================================================================="

    echo ""
    print_info "Step 5: Getting Function App Managed Identity..."
    PRINCIPAL_ID=$(az functionapp identity show \
        --name "$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query principalId \
        --output tsv)

    print_success "Managed Identity Principal ID: $PRINCIPAL_ID"

    echo ""
    print_warning "====================================================================="
    print_warning "IMPORTANT: Post-Deployment Steps Required"
    print_warning "====================================================================="
    print_warning ""
    print_warning "You must grant the Function App read access to the source storage:"
    print_warning ""
    print_warning "Run this command:"
    print_warning ""
    echo -e "${YELLOW}  SOURCE_STORAGE_ACCOUNT=\$(az storage account show \\
    --name bpavanvnetlogstorage \\
    --resource-group bpavan-vnet-logs \\
    --query id \\
    --output tsv)

  az role assignment create \\
    --assignee $PRINCIPAL_ID \\
    --role \"Storage Blob Data Reader\" \\
    --scope \$SOURCE_STORAGE_ACCOUNT${NC}"
    print_warning ""
    print_warning "====================================================================="

    echo ""
    print_warning "====================================================================="
    print_warning "NEXT STEP: Deploy Function Code"
    print_warning "====================================================================="
    print_warning ""
    print_warning "The infrastructure is ready, but you need to deploy your function code."
    print_warning ""
    print_warning "Quick deployment:"
    print_warning ""
    echo -e "${YELLOW}  cd /Users/bpavan/repos/logint/nr/newrelic-azure-functions
  npm run package:logforwarder
  az functionapp deployment source config-zip \\
    --resource-group $RESOURCE_GROUP \\
    --name $FUNCTION_APP_NAME \\
    --src LogForwarder.zip
  az functionapp restart --resource-group $RESOURCE_GROUP --name $FUNCTION_APP_NAME${NC}"
    print_warning ""
    print_warning "For detailed instructions, see: vnet-flow-logs-spike/DEPLOY_CODE.md"
    print_warning "====================================================================="

    echo ""
    print_success "Deployment script completed!"
    print_info "After deploying code, monitor logs with: az webapp log tail --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP"

else
    print_error "Deployment failed. Check the output above for details."
    exit 1
fi