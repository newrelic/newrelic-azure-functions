This function collects logs (e.g. Activity and Diagnostic logs) from Azure Event Hubs and forwards them to New Relic.

## Create the Azure Function App

1. Log in to the Azure Portal and create a new [Function App](https://docs.microsoft.com/en-us/azure/azure-functions/functions-create-first-azure-function).
2. Add the following in the **Instance Details** section of the **Basics** tab:

| Field | Value |
|---|---|
|Publish|Code|
|Runtime stack|Node.js|
|Version|12|

3. Select the **Hosting** tab and select **Windows** as the Operating System
4. Fill out remaining required fields as desired and **Create** your Function App.

## Create and Deploy the Azure Function

1. Once your function app has been created, expand it and select the `+` button next to **Functions**
2. Click **In-portal** followed by **More templates...**. Next click **Finish and view templates**.
3. Search for "event hub" and select **Azure Event Hub trigger**
4. Define the desired **Name**, **Event Hub connection** and **Event Hub name** of the Event Hub to collect logs from, as well as the **Event Hub consumer group**
5. Paste the New Relic [function code](index.js) in the function's existing `index.js` and click **Save**.
6. Navigate to the **Integrate** tab and verify **Event parameter name** is set to `eventHubMessages` and **Event Hub Cardinality** is set to `Many`.
7. [Configure](#azure-application-settings) your function's Application settings and define the desired application settings. `NR_INSERT_KEY` must be configured here.

## Azure Application Settings

Parameters to be configured in your Azure function's [application settings](https://docs.microsoft.com/en-us/azure/azure-functions/functions-how-to-use-azure-function-app-settings).

| Property | Required or Optional | Default Value | Description
|---|---|---|---|
| NR_INSERT_KEY | Required | `none` | Your New Relic Insights [insert key](https://docs.newrelic.com/docs/insights/insights-api/get-data/query-insights-event-data-api#register) |
| NR_ENDPOINT |  Optional | `https://log-api.newrelic.com/log/v1` | New Relic Logs [ingestion endpoint](https://docs.newrelic.com/docs/logs/new-relic-logs/log-api/introduction-log-api#endpoint) |
| NR_TAGS | Optional | `none` | Attributes to be added to all logs forwarded to New Relic. Semicolon delimited (e.g. `env:prod;team:myTeam`) |
| NR_MAX_RETRIES | Optional | `3` | Number of times the function will attempt to resend data |
| NR_RETRY_INTERVAL | Optional | `2000` | Interval between retry attempts in milliseconds |


### Finding your Insert Key

* Your New Relic Insights [insert keys](https://docs.newrelic.com/docs/insights/insights-api/get-data/query-insights-event-data-api#register) can be found here:
`https://insights.newrelic.com/accounts/<ACCOUNT_ID>/manage/api_keys`
