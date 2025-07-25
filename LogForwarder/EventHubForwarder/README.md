An Azure Resource Manager template to export Azure Platform logs to New Relic.

## How Does It Work?

This integration creates and configures the Azure resources necessary to efficiently forwards logs from an Azure Event Hub to New Relic. 
It relies on events managed by Azure Event Hub, Event Hub subsequently batches and triggers an Azure Function to handle the transport to New Relic.

Currently, this integration allows you to create resources to targets Azure Activity logs. If you have other log events that you would like to see shipped using Event hub trigger, [tell us about your use case](https://github.com/newrelic/newrelic-azure-functions/issues).

## Installation

This integration requires both a New Relic and Azure account.

### Install through New Relic Marketplace

1. Visit the New Relic Marketplace \[[US](https://one.newrelic.com/marketplace)|[EU](https://one.newrelic.com/marketplace)\]
2. Search for "Microsoft Azure Event Hub"
3. Click on the "Microsoft Azure Event Hub" tile and follow the steps.

### Install Using Azure Portal

Retrieve your [New Relic License Key](https://docs.newrelic.com/docs/apis/intro-apis/new-relic-api-keys/#ingest-license-key).
Then click the button below to start the installation process via the Azure Portal.

[Deploy to Azure](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fnewrelic%2Fnewrelic-azure-functions%2Fmaster%2FarmTemplates%2Fazuredeploy-eventhubforwarder.json)
using the [Azure ARM template](../armTemplates/azuredeploy-eventhubforwarder.json).

### Azure Application Settings

Parameters that can be configured in your Azure Resource Manager Template

| Parameter  | Required | Default Value | Description
|---|---|---|---|
| New Relic License Key  | yes | `none` | Your New Relic [License key](https://docs.newrelic.com/docs/apis/intro-apis/new-relic-api-keys/) |
| Event Hub Namespace | no | `none` | In case you already have a Event hub namespace configured |
| New Relic Endpoint  |  no | `https://log-api.newrelic.com/log/v1` | New Relic Logs [ingestion endpoint](https://docs.newrelic.com/docs/logs/new-relic-logs/log-api/introduction-log-api#endpoint) |
| Log Custom Attributes  | no | `none` | Attributes to be added to all logs forwarded to New Relic. Semicolon delimited (e.g. `env:prod;team:myTeam`) |
| Max Retries To Resend Logs  | no | `3` | Number of times the function will attempt to resend data |
| Retry Interval  | no | `2000` | Interval between retry attempts in milliseconds |
| Event Hub Namespace Name | no | `none` | Namespace in which hub are allocated. Leave this blank for a new namespace to be created automatically |
| Event hub Name | no | `none` | Name of the Event Hub where logs are allocated. Leave this blank for a new Event Hub to be created automatically |
| scalingMode | no | `Basic` | The scaling mode option configured for the New Relic Azure Log Forwarder. Setting this to `Enterprise` will configure autoscaling. <br> <br> > `Note`: If you upgrade from Basic to Enterprise you will need to reprovision the EventHub due to the Azure limit that a Standard SKU cannot change partition counts. |
| Enable Administrative Azure Activity Logs | no | `false` | Contains the record of all create, update, delete, and action operations performed through Resource Manager. More information about Administrative category in [azure official documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/essentials/activity-log-schema#administrative-category). |
| Enable Alert Azure Activity Logs | no | `false` | Contains the record of all activations of classic Azure alerts. More information about Alert category in [azure official documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/essentials/activity-log-schema#alert-category). |
| Enable Policy Azure Activity Logs | no | `false` | Contains records of all effect action operations performed by Azure Policy. More information about Policy category in [azure official documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/essentials/activity-log-schema#policy-category). |
| Enable Autoscale Azure Activity Logs | no | `false` | Contains the record of any events related to the operation of the autoscale engine based on any autoscale settings you have defined in your subscription. More information about Autoscale category in [azure official documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/essentials/activity-log-schema#autoscale-category). |
| Enable Recommendation Azure Activity Logs | no | `false` | Contains recommendation events from Azure Advisor. More information about Recommendation category in [azure official documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/essentials/activity-log-schema#recommendation-category). |
| Enable Resource Health Azure Activity Logs | no | `false` | Contains the record of any resource health events that have occurred to your Azure resources. More information about Resource Health category in [azure official documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/essentials/activity-log-schema#resource-health-category). |
| Enable Security Azure Activity Logs | no | `false` | Contains the record of any alerts generated by Azure Security Center. More information about Security category in [azure official documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/essentials/activity-log-schema#security-category). |
| Enable Service Health Azure Activity Logs | no | `false` | Contains the record of any service health incidents that have occurred in Azure. More information about Recommendation category in [azure official documentation](. More information about Recommendation category in [azure official documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/essentials/activity-log-schema#recommendation-category). |

Alternatively you can configure this template that will automatically create the resource, deployed them and configure Activity Logs to forward them to New Relic.

### Architecture 

![ehub-template-diagram](https://github.com/newrelic/newrelic-azure-functions/blob/master/screenshots/EventHub/ehub-template-diagram.png?raw=true)

## Manually create an Azure Function App

1. Log in to the Azure Portal and create a new [Function App](https://docs.microsoft.com/en-us/azure/azure-functions/functions-create-first-azure-function).
2. Add the following in the **Instance Details** section of the **Basics** tab:

| Field | Value |
|---|---|
|Publish|Code|
|Runtime stack|Node.js|
|Version|12|

![ehub1](https://github.com/newrelic/newrelic-azure-functions/blob/master/screenshots/EventHub/ehub1.png?raw=true)

3. Select the **Hosting** tab and select **Windows** as the Operating System
4. Fill out remaining required fields as desired and **Create** your Function App.

### Create and Deploy the Azure Function

1. Once your function app has been created, expand it and select the `+` button next to **Functions** 
![func-plus](https://github.com/newrelic/newrelic-azure-functions/blob/master/screenshots/EventHub/func-plus.png?raw=true)
2. Click **In-portal** followed by **More templates...**. Next click **Finish and view templates**.
![ehub3](https://github.com/newrelic/newrelic-azure-functions/blob/master/screenshots/EventHub/ehub3.png?raw=true)
3. Search for "event hub" and select **Azure Event Hub trigger**
![ehub5](https://github.com/newrelic/newrelic-azure-functions/blob/master/screenshots/EventHub/ehub5.png?raw=true)
4. Define the desired **Name**, **Event Hub connection** and **Event Hub name** of the Event Hub to collect logs from, as well as the **Event Hub consumer group**
![ehub6](https://github.com/newrelic/newrelic-azure-functions/blob/master/screenshots/EventHub/ehub6.png?raw=true)
5. Paste the New Relic [function code](index.js) in the function's existing `index.js` and click **Save**.
6. Navigate to the **Integrate** tab and verify **Event parameter name** is set to `eventHubMessages` and **Event Hub Cardinality** is set to `Many`.
![ehub7](https://github.com/newrelic/newrelic-azure-functions/blob/master/screenshots/EventHub/ehub7.png?raw=true)
7. [Configure](#azure-application-settings) your function's Application settings and define the desired application settings. `NR_INSERT_KEY` must be configured here.

### Application Settings

Parameters to be configured in your Azure function's [application settings](https://docs.microsoft.com/en-us/azure/azure-functions/functions-how-to-use-azure-function-app-settings).

| Property | Required or Optional | Default Value | Description
|---|---|---|---|
| NR_INSERT_KEY | Required | `none` | Your New Relic Insights [insert key](https://docs.newrelic.com/docs/insights/insights-api/get-data/query-insights-event-data-api#register) |
| NR_ENDPOINT |  Optional | `https://log-api.newrelic.com/log/v1` | New Relic Logs [ingestion endpoint](https://docs.newrelic.com/docs/logs/new-relic-logs/log-api/introduction-log-api#endpoint) |
| NR_TAGS | Optional | `none` | Attributes to be added to all logs forwarded to New Relic. Semicolon delimited (e.g. `env:prod;team:myTeam`) |
| NR_MAX_RETRIES | Optional | `3` | Number of times the function will attempt to resend data |
| NR_RETRY_INTERVAL | Optional | `2000` | Interval between retry attempts in milliseconds |
