This function collects logs from Azure Blob Storage and forwards the contents to [New Relic Logs](https://docs.newrelic.com/docs/logs).

## Create the Function App

1. Log in to the Azure Portal and create a [new Function App](https://docs.microsoft.com/en-us/azure/azure-functions/functions-create-first-azure-function).
2. Add the following in the **Instance Details** section of the **Basics** tab:

| Field | Value |
|---|---|
|Publish|Code|
|Runtime stack|Node.js|
|Version|12|

![blob1](https://github.com/newrelic/newrelic-azure-functions/blob/master/screenshots/BlobForwarder/blob1.png?raw=true)

3. Select the **Hosting** tab and select **Windows** as the Operating System
4. Fill out remaining required fields as desired.

## Create and Deploy the Azure Function

1. Once your function app has been created, select the `+` button next to **Functions**
![func-plus](https://github.com/newrelic/newrelic-azure-functions/blob/master/screenshots/EventHub/func-plus.png?raw=true)
2. Click **In-portal** followed by **More templates...**. Next click **Finish and view templates**.
3. Search for "blob" and select **Azure Blob Storage trigger**
![blob-trig](https://github.com/newrelic/newrelic-azure-functions/blob/master/screenshots/BlobForwarder/blob-trig.png?raw=true)
4. Define the desired **Name**, **Path** to your blob, and **Storage account connection**
![blob3](https://github.com/newrelic/newrelic-azure-functions/blob/master/screenshots/BlobForwarder/blob3.png?raw=true)
5. Paste the New Relic [function code](index.js?raw=true) in the function's existing `index.js` and click **Save**.
6. Navigate to the **Integrate** tab and verify **Blob parameter name** is set to `myBlob`.
![blob4](https://github.com/newrelic/newrelic-azure-functions/blob/master/screenshots/BlobForwarder/blob4.png?raw=true)
7. Configure your function's [Application settings](https://docs.microsoft.com/en-us/azure/azure-functions/functions-how-to-use-azure-function-app-settings) and define the desired application settings. `NR_INSERT_KEY` must be configured here.

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

