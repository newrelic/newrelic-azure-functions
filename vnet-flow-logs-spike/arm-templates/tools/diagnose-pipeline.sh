#!/bin/bash

###############################################################################
# VNet Flow Logs Pipeline Diagnostics
###############################################################################

set -e

RESOURCE_GROUP="bpavan-vnet-logs-arm"
FUNCTION_APP="bpavan-vnet-func-7lk6nyehuzkgi"
STORAGE_ACCOUNT="bpavan7lk6nyehuzkgi"
EVENT_GRID_TOPIC="bpavan-vnet-egtopic-7lk6nyehuzkgi"
EVENT_HUB_NS="bpavan-vnet-eventhub-ns-7lk6nyehuzkgi"
EVENT_HUB="bpavan-vnet-eventhub"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=====================================================================${NC}"
echo -e "${BLUE}VNet Flow Logs Pipeline Diagnostics${NC}"
echo -e "${BLUE}=====================================================================${NC}"
echo ""

# 1. Check VNet Flow Logs
echo -e "${BLUE}[1/7] Checking VNet Flow Logs Status...${NC}"
az network watcher flow-log show \
  --location canadacentral \
  --name bpavan-vnet-flowlogs \
  --query "{Enabled:enabled, Target:targetResourceId, Storage:storageId, Format:format.type, Version:format.version}" \
  -o table

echo ""

# 2. Check PT1H.json files
echo -e "${BLUE}[2/7] Checking for PT1H.json files in storage...${NC}"
BLOB_COUNT=$(az storage blob list \
  --account-name $STORAGE_ACCOUNT \
  --container-name insights-logs-flowlogflowevent \
  --auth-mode key \
  --query "length([])" \
  -o tsv 2>/dev/null || echo "0")

if [ "$BLOB_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓ Found $BLOB_COUNT PT1H.json file(s)${NC}"
    echo ""
    echo "Latest files:"
    az storage blob list \
      --account-name $STORAGE_ACCOUNT \
      --container-name insights-logs-flowlogflowevent \
      --auth-mode key \
      --query "[].{Name:name, Size:properties.contentLength, Modified:properties.lastModified}" \
      -o table 2>/dev/null | head -10
else
    echo -e "${RED}✗ No PT1H.json files found${NC}"
    echo -e "${YELLOW}Wait 5-10 minutes for Network Watcher to generate first file${NC}"
fi

echo ""

# 3. Check Event Grid System Topic
echo -e "${BLUE}[3/7] Checking Event Grid System Topic...${NC}"
az eventgrid system-topic show \
  --resource-group $RESOURCE_GROUP \
  --name $EVENT_GRID_TOPIC \
  --query "{Name:name, ProvisioningState:provisioningState, Source:source}" \
  -o table

echo ""

# 4. Check Event Grid Subscription
echo -e "${BLUE}[4/7] Checking Event Grid Subscription...${NC}"
az eventgrid system-topic event-subscription show \
  --resource-group $RESOURCE_GROUP \
  --system-topic-name $EVENT_GRID_TOPIC \
  --name bpavan-vnet-egsub-7lk6nyehuzkgi \
  --query "{Name:name, ProvisioningState:provisioningState, EndpointType:destination.endpointType, FilterSubjectEndsWith:filter.subjectEndsWith}" \
  -o table

echo ""

# 5. Check Event Hub
echo -e "${BLUE}[5/7] Checking Event Hub...${NC}"
az eventhubs eventhub show \
  --resource-group $RESOURCE_GROUP \
  --namespace-name $EVENT_HUB_NS \
  --name $EVENT_HUB \
  --query "{Name:name, Status:status, PartitionCount:partitionCount}" \
  -o table

echo ""

# 6. Check Function App
echo -e "${BLUE}[6/7] Checking Function App...${NC}"
az functionapp show \
  --resource-group $RESOURCE_GROUP \
  --name $FUNCTION_APP \
  --query "{Name:name, State:state, RuntimeVersion:siteConfig.linuxFxVersion, AppInsights:kind}" \
  -o table

echo ""

# Check if function is deployed
echo "Checking deployed functions:"
FUNCTION_COUNT=$(az functionapp function list \
  --resource-group $RESOURCE_GROUP \
  --name $FUNCTION_APP \
  --query "length([])" \
  -o tsv 2>/dev/null || echo "0")

if [ "$FUNCTION_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓ Function code is deployed${NC}"
    az functionapp function list \
      --resource-group $RESOURCE_GROUP \
      --name $FUNCTION_APP \
      --query "[].name" \
      -o table
else
    echo -e "${RED}✗ No functions found - CODE NOT DEPLOYED!${NC}"
    echo -e "${YELLOW}You need to deploy the function code manually.${NC}"
fi

echo ""

# 7. Check Application Insights
echo -e "${BLUE}[7/7] Checking Application Insights...${NC}"
APP_INSIGHTS=$(az functionapp config appsettings list \
  --resource-group $RESOURCE_GROUP \
  --name $FUNCTION_APP \
  --query "[?name=='APPLICATIONINSIGHTS_CONNECTION_STRING'].value | [0]" \
  -o tsv)

if [ -n "$APP_INSIGHTS" ]; then
    echo -e "${GREEN}✓ Application Insights is configured${NC}"
    echo "Connection String: ${APP_INSIGHTS:0:50}..."
else
    echo -e "${RED}✗ Application Insights not configured${NC}"
fi

echo ""
echo -e "${BLUE}=====================================================================${NC}"
echo -e "${BLUE}Diagnostic Summary${NC}"
echo -e "${BLUE}=====================================================================${NC}"

# Summary
if [ "$BLOB_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓ VNet Flow Logs are generating (found PT1H.json files)${NC}"
else
    echo -e "${YELLOW}⚠ Waiting for first PT1H.json file (5-10 minutes after deployment)${NC}"
fi

if [ "$FUNCTION_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓ Function code is deployed${NC}"
else
    echo -e "${RED}✗ Function code is NOT deployed${NC}"
    echo ""
    echo -e "${YELLOW}ACTION REQUIRED: Deploy function code${NC}"
    echo ""
    echo "Run these commands:"
    echo -e "${GREEN}"
    cat <<EOF
cd /Users/bpavan/repos/logint/nr/newrelic-azure-functions
npm run package:logforwarder
az functionapp deployment source config-zip \\
  --resource-group $RESOURCE_GROUP \\
  --name $FUNCTION_APP \\
  --src LogForwarder.zip
az functionapp restart --resource-group $RESOURCE_GROUP --name $FUNCTION_APP
EOF
    echo -e "${NC}"
fi

echo ""
echo -e "${BLUE}=====================================================================${NC}"
echo -e "${BLUE}Next Steps${NC}"
echo -e "${BLUE}=====================================================================${NC}"
echo ""
echo "1. View Function Logs (Portal):"
echo "   https://portal.azure.com/#@/resource/subscriptions/9c99d7c5-7653-4b53-ae61-daeff13d8569/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/sites/$FUNCTION_APP/logStream"
echo ""
echo "2. View Function Logs (CLI):"
echo "   az webapp log tail --resource-group $RESOURCE_GROUP --name $FUNCTION_APP"
echo ""
echo "3. View Application Insights Logs:"
echo "   https://portal.azure.com/#@/resource/subscriptions/9c99d7c5-7653-4b53-ae61-daeff13d8569/resourceGroups/$RESOURCE_GROUP/providers/microsoft.insights/components/*/logs"
echo ""
echo "4. Generate more traffic (deploy test VM):"
echo "   See GENERATE_TRAFFIC.md"
echo ""
