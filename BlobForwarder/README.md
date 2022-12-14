This function collects logs from Azure Blob Storage and forwards the contents to [New Relic Logs](https://docs.newrelic.com/docs/logs).

## How Does It Work?
This integration creates and configures the Azure resources necessary to efficiently forwards logs from an Azure Blob Storage to New Relic.
It relies on Azure Blob Storage trigger, which will trigger an Azure Function to handle the transport to New Relic.

## Installation
This integration requires both a New Relic and Azure account.

### Install Using Azure Portal
Retrieve your [New Relic License Key](https://docs.newrelic.com/docs/apis/intro-apis/new-relic-api-keys/#ingest-license-key).
Then click the button below to start the installation process via the Azure Portal.

[![Deploy to Azure](https://azuredeploy.net/deploybutton.png)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fnewrelic%2Fnewrelic-azure-functions%2Fmaster%2FarmTemplates%2Fazuredeploy-blobforwarder.json)

### Azure Application Settings
Parameters that can be configured in your Azure Resource Manager Template

| Parameter  | Required | Default Value | Description
|---|---|---|---|
| New Relic License Key  | yes | `none` | Your New Relic [License key](https://docs.newrelic.com/docs/apis/intro-apis/new-relic-api-keys/). |
| Storage Account Name | yes | `none` | Storage Account Name in which the Blobs are allocated. If a new name is provided, a new Storage Account will be created. More information about Storage Account in [azure official documentation](https://docs.microsoft.com/en-us/azure/storage/). |
| Storage Account Redundancy | yes | `Standard_LRS` | The data in your Azure storage account is always replicated to ensure durability and high availability. Choose a replication strategy that matches your existing storage account or a new one to be created. More information about Storage Account Redundancy in [azure official documentation](https://docs.microsoft.com/en-us/azure/storage/common/storage-redundancy). |
| Storage Account Kind | yes | `StorageV2` | Indicates the type of storage account. Each type supports different features and has its own pricing model. Consider these differences before you create a storage account to determine the type of account that's best for your applications or choose one that match your existing storage account. More information about Storage Account Kind in [azure official documentation](https://docs.microsoft.com/en-us/azure/storage/common/storage-account-overview#types-of-storage-accounts). |
| Storage Account Location | yes | `none` | Location where the storage account resides. |
| Storage Account Container | yes | `none` | Container name inside the Storage Account. More information about Blob storages in [azure official documentation](https://docs.microsoft.com/en-us/azure/storage/blobs/storage-blobs-introduction). |
| New Relic Endpoint  |  no | `https://log-api.newrelic.com/log/v1` | New Relic Logs [ingestion endpoint](https://docs.newrelic.com/docs/logs/new-relic-logs/log-api/introduction-log-api#endpoint) |
| Max Retries To Resend Logs  | no | `3` | Number of times the function will attempt to resend data |
| Retry Interval  | no | `2000` | Interval between retry attempts in milliseconds |

### Architecture
![blob-template-diagram](https://github.com/newrelic/newrelic-azure-functions/blob/master/screenshots/BlobForwarder/blob4.png?raw=true)

## Manually create an Azure Function App

1. Log in to the Azure Portal and create a [new Function App](https://docs.microsoft.com/en-us/azure/azure-functions/functions-create-first-azure-function).
2. Add the following in the **Instance Details** section of the **Basics** tab:

| Field | Value |
|---|---|
|Publish|Code|
|Runtime stack|Node.js|
|Version|12|

![blob1](https://github.com/newrelic/newrelic-azure-functions/blob/master/screenshots/BlobForwarder/blob1.png?raw=true)

3. Select the region that match where the Blobs are storaged
4. Select the **Hosting** tab and select **Windows** as the Operating System
5. Fill out remaining required fields as desired.

## Create and Deploy the Azure Function

1. Once your function app has been created, click and open it
2. In the left menu, click **Functions**
   ![blob2](https://github.com/newrelic/newrelic-azure-functions/blob/master/screenshots/BlobForwarder/blob2.png?raw=true)
3. Click on **Create** and search for "blob" and select **Azure Blob Storage trigger**
   ![blob3](https://github.com/newrelic/newrelic-azure-functions/blob/master/screenshots/BlobForwarder/blob3.png?raw=true)
4. Define the desired **Name**, **Path** to your blob, and **Storage account connection** (Path follows the convention `container/blob`. In order to trigger all blobs inside a container use the `{name}` parameter. eg. `my-container/{name}`)
5. Paste the New Relic [function code](index.js?raw=true) in the function's existing `index.js` and click **Save**.
6. Navigate to the **Integrate** tab and verify **Blob parameter name** is set to `myBlob`.
7. Configure your function's [Application settings](https://docs.microsoft.com/en-us/azure/azure-functions/functions-how-to-use-azure-function-app-settings) and define the desired application settings. `NR_INSERT_KEY` must be configured here.

## NewRelic Azure Application Settings

Parameters to be configured in your Azure function's [application settings](https://docs.microsoft.com/en-us/azure/azure-functions/functions-how-to-use-azure-function-app-settings). 

| Property | Required or Optional | Default Value | Description
|---|---|---|---|
| NR_LICENSE_KEY | Required | `none` | Your New Relic License Key [license key](https://docs.newrelic.com/docs/apis/intro-apis/new-relic-api-keys/) |
| NR_ENDPOINT |  Optional | `https://log-api.newrelic.com/log/v1` | New Relic Logs [ingestion endpoint](https://docs.newrelic.com/docs/logs/new-relic-logs/log-api/introduction-log-api#endpoint) |
| NR_TAGS | Optional | `none` | Attributes to be added to all logs forwarded to New Relic. Semicolon delimited (e.g. `env:prod;team:myTeam`) |
| NR_MAX_RETRIES | Optional | `3` | Number of times the function will attempt to resend data |
| NR_RETRY_INTERVAL | Optional | `2000` | Interval between retry attempts in milliseconds |


### Finding your NR_LICENSE_KEY Key

* Your New Relic Licence Key [license keys](https://docs.newrelic.com/docs/apis/intro-apis/new-relic-api-keys/) can be found here:
`https://one.newrelic.com/launcher/api-keys-ui.api-keys-launcher`
