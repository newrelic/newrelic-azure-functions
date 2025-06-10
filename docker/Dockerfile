FROM mcr.microsoft.com/azure-functions/node:4-node20-slim

ENV AzureWebJobsScriptRoot=/home/site/wwwroot \
    AzureFunctionsJobHost__Logging__Console__IsEnabled=true \
    NEW_RELIC_NO_CONFIG_FILE=true \
    NEW_RELIC_DISTRIBUTED_TRACING_ENABLED=true \
    NEW_RELIC_LOG=stdout


WORKDIR /home/site/wwwroot 

COPY package.json .
COPY host.json .

RUN mkdir -p EventHubForwarder/
# Copy the function's index.js and function.json into its folder
COPY LogForwarder/index.js EventHubForwarder/index.js
COPY LogForwarder/EventHubForwarder/function.json EventHubForwarder/function.json

RUN npm install --no-audit