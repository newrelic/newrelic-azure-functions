This function collects logs from Azure Blob Storage and forwards the contents to [New Relic Logs](https://docs.newrelic.com/docs/logs).

## How Does It Work?

This integration creates and configures the Azure resources necessary to efficiently forwards logs from an Azure Blob Storage to New Relic. 
It relies on Azure Blob Storage trigger, which will trigger an Azure Function to handle the log transport to New Relic.

## Installation

This integration requires both a New Relic and Azure account.

You can install this integration using one of two methods:
- **Automatic Installation** (recommended): Uses Azure ARM templates to automatically create and configure all resources
- **Manual Installation**: Step-by-step manual setup for users who want more control or have specific requirements

---

## Automatic Installation (Recommended)

The automatic installation uses Azure Resource Manager (ARM) templates to create and configure all necessary resources automatically.

### Option 1: Guided Install through New Relic Marketplace

1. Visit the New Relic Marketplace \[[US](https://one.newrelic.com/marketplace)|[EU](https://one.newrelic.com/marketplace)\]
2. Search for "Microsoft Azure Blob Storage"
3. Click on the "Microsoft Azure Blob Storage" tile
4. Select your New Relic account and follow the guided installation wizard

### Option 2: Install Using Azure Portal

1. Retrieve your [New Relic License Key](https://docs.newrelic.com/docs/apis/intro-apis/new-relic-api-keys/#ingest-license-key)
2. Click the button below to start the installation process via the Azure Portal

[Deploy to Azure](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fnewrelic%2Fnewrelic-azure-functions%2Fmaster%2FarmTemplates%2Fazuredeploy-blobforwarder.json)
using the [Azure ARM template](../armTemplates/azuredeploy-blobforwarder.json).

3. Fill in the required parameters in the Azure Portal deployment form (see parameters table below)
4. **Important**: For most deployments, leave `Disable Public Access To Storage Account` set to `false` (default). Only set to `true` if you require private network deployment. See the [Architecture](#architecture) section below for details on the differences.

### ARM Template Parameters

Parameters that can be configured in your Azure Resource Manager Template

| Parameter  | Required | Default Value | Description
|---|---|---|---|
| New Relic License Key  | yes | `none` | Your New Relic [License key](https://docs.newrelic.com/docs/apis/intro-apis/new-relic-api-keys/). |
| Target Storage Account Name | yes | `none` | Name of the existing Azure Storage Account that contains the logs you want to forward. |
| Target Container Name | yes | `none` | Name of the container inside the target Storage Account that contains the log blobs. |
| Location | no | Resource group location | Region where the Function App and associated resources will be deployed. Defaults to the resource group's location. |
| New Relic Endpoint  |  no | `https://log-api.newrelic.com/log/v1` | New Relic Logs [ingestion endpoint](https://docs.newrelic.com/docs/logs/log-api/introduction-log-api/#endpoint). Use `https://log-api.eu.newrelic.com/log/v1` for EU accounts. |
| Max Retries To Resend Logs  | no | `3` | Number of times the function will attempt to resend data if there's a failure. |
| Retry Interval  | no | `2000` | Interval between retry attempts in milliseconds. |
| Disable Public Access To Storage Account | no | `false` | When set to `true`, disables public network access to the internal storage account used by the Function App. This creates a private network deployment with VNet integration, private endpoints, private DNS zones, and requires a Basic hosting plan or higher. When `false`, uses standard Consumption plan with public access. |

### Architecture

The ARM template supports two deployment architectures based on the `disablePublicAccessToStorageAccount` parameter:

#### Standard Deployment (Default: `disablePublicAccessToStorageAccount=false`)

**Network Configuration:**
- Public internet access enabled for both Function App and internal storage account
- No VNet integration
- Standard Consumption plan (serverless)

**Resources Created (4 resources):**

Always Created (3):
- Function App
- Internal Storage Account (public access)
- App Service Plan

Standard Deployment Only (1):
- ZipDeploy extension

**Deployment Method:** ZipDeploy extension deploys the function code

**Use Case:** Standard deployments, no network isolation requirements

![Blob Standard Architecture](../../screenshots/BlobForwarder/blob-standard-architecture.png)

#### Private Network Deployment (`disablePublicAccessToStorageAccount=true`)

**Network Configuration:**
- **Public access disabled** for both Function App and internal storage account
- **VNet integration** with private networking
- Communication flows through private endpoints within the VNet
- DNS resolution handled via Private DNS Zones
- Requires Basic plan or higher for VNet integration support

**Resources Created (21 resources):**

Always Created (3):
- Function App
- Internal Storage Account (private access only)
- App Service Plan (Basic plan or higher)

Private VNet Infrastructure (18):
- 1 Virtual Network with 2 subnets:
  - Function subnet (for Function App VNet integration)
  - Private endpoints subnet
- 4 Private Endpoints (file, blob, queue, table storage services)
- 4 Private DNS Zones (privatelink.blob/file/queue/table.core.windows.net)
- 4 Virtual Network Links (connecting DNS zones to VNet)
- 4 Private DNS Zone Groups (connecting private endpoints to DNS zones)
- 1 Network Configuration (VNet integration for Function App)

**Deployment Method:** WEBSITE_RUN_FROM_PACKAGE with GitHub URL (public ZipDeploy endpoint not accessible)

**Use Case:** Compliance requirements, corporate security policies requiring network isolation, no public internet access

![Blob Private VNet Architecture](../../screenshots/BlobForwarder/blob-private-network-architecture.png)

**Key Differences:**

| Aspect | Standard | Private Network |
|--------|----------|-----------------|
| Network Access | Public internet | Private VNet only |
| VNet Integration | None | Full VNet integration with private endpoints |
| Storage Access | Public endpoints | Private endpoints only |
| Deployment Method | ZipDeploy extension | Run-from-package URL |
| Resources Created | 4 resources | 21 resources |

**Note**: The manual installation instructions below create a deployment equivalent to the **Standard** architecture with public access.

---

## Manual Installation

Use this method if you want to manually create and configure the Function App yourself, or if you need more control over the setup process.

### Prerequisites

Before starting the manual installation, ensure you have:
- An existing Azure Storage Account with a container that contains the logs you want to forward
- You can verify your container exists by navigating to the storage account → **Data storage** → **Containers**
- Note the container name (e.g., `logs`) as you'll need it for the `CONTAINER_NAME` setting

![Storage Account Containers](../../screenshots/BlobForwarder/blob-storage-containers.png)

**Getting the Target Storage Account Connection String:**

You'll need the connection string from your target storage account (where logs are stored). To get the `TargetAccountConnection` value, go to your target storage account → **Security + networking** → **Access keys** → Click **Show** next to "Connection string" and copy the value.

![Storage Account Connection String](../../screenshots/BlobForwarder/blob-storage-connection.png)

### Step 1: Create an Azure Function App

1. Log in to the Azure Portal and create a [new Function App](https://docs.microsoft.com/en-us/azure/azure-functions/functions-create-first-azure-function).

2. On the **Hosting** tab (if shown first), select **Consumption (Windows)** as the hosting plan.

3. In the **Basics** tab, configure the following:

| Field | Value |
|---|---|
| Subscription | Your Azure subscription |
| Resource Group | Create new or select existing |
| Function App name | Globally unique name |
| Runtime stack | **Node.js** |
| Version | **22 LTS** |
| Region | Select your preferred region |
| Operating System | **Windows** |

![Create Function App - Basics](../../screenshots/BlobForwarder/blob-create-basics.png)

4. Complete the **Storage** and **Networking** tabs as needed for your environment.

5. Click **Review + Create**, then **Create** to provision your Function App.

6. Wait 2-3 minutes for deployment to complete.

### Step 2: Deploy the Azure Function

Azure Functions v4 uses a package deployment model. Code cannot be edited directly in the Azure Portal. Instead, you must deploy a pre-built package and configure application settings.

#### Configure Application Settings

1. Navigate to your Function App → **Settings** → **Configuration**
2. Click the **Application settings** tab
3. Add the following settings by clicking **+ New application setting** for each:

![Function App Application Settings](../../screenshots/BlobForwarder/function-application-settings.png)

#### Required Settings

| Name | Value                                                                                            | Description |
|------|--------------------------------------------------------------------------------------------------|-------------|
| `NR_LICENSE_KEY` | Your New Relic License Key                                                                       | Found at [one.newrelic.com](https://one.newrelic.com) → API Keys → License Key |
| `BLOB_FORWARDER_ENABLED` | `true`                                                                                           | Enables the Blob Storage trigger. **Must be lowercase** `true`. |
| `CONTAINER_NAME` | `your-container-name`                                                                            | Name of the container in the target storage account. Example: `logs` to monitor all blobs in the `logs` container. Do NOT include `/{name}` - the function adds this automatically. |
| `TargetAccountConnection` | Storage account connection string                                                                | Connection string from your target storage account (where logs are stored). Found in Storage Account → Security + networking → Access keys → Connection string. |
| `WEBSITE_RUN_FROM_PACKAGE` | `https://github.com/newrelic/newrelic-azure-functions/releases/latest/download/LogForwarder.zip` | URL to the deployment package. This tells Azure to download and run the latest function code from GitHub. |

#### Optional Settings

| Name | Default Value | Description |
|------|---------------|-------------|
| `NR_ENDPOINT` | `https://log-api.newrelic.com/log/v1` | New Relic Logs API endpoint. Use `https://log-api.eu.newrelic.com/log/v1` for EU region accounts. |
| `NR_TAGS` | _(empty)_ | Custom attributes to add to all forwarded logs. Semicolon-delimited format: `env:prod;team:platform;app:myapp` |
| `NR_MAX_RETRIES` | `3` | Number of retry attempts if sending logs to New Relic fails. |
| `NR_RETRY_INTERVAL` | `2000` | Milliseconds to wait between retry attempts. |

#### Auto-Configured Settings (Verify Exist)

These settings are automatically created when you provision the Function App. Verify they exist and have the correct values:

| Name | Expected Value | Notes |
|------|----------------|-------|
| `FUNCTIONS_EXTENSION_VERSION` | `~4` | Azure Functions v4 runtime. |
| `FUNCTIONS_WORKER_RUNTIME` | `node` | Node.js worker runtime. May be auto-managed on some hosting plans. |
| `WEBSITE_NODE_DEFAULT_VERSION` | `~22` | Node.js version 22. May be auto-managed on some hosting plans. |
| `AzureWebJobsStorage` | _(connection string)_ | Internal storage account used by the Function App for state management. Auto-created. |

![Application Settings Configured](../../screenshots/BlobForwarder/blob-app-settings.png)

4. Click **Save** at the top of the page
5. Click **Continue** to confirm the Function App restart

#### Deploy the Function Package

1. Go to Function App → **Overview**
2. Click **Restart** to ensure all settings are applied and the package is downloaded
3. Wait 30-60 seconds for the deployment to complete

#### Verify Function Deployment

1. Navigate to **Functions** in the left menu
2. You should see **BlobForwarder** listed with Status: **Enabled**

![BlobForwarder Function Deployed](../../screenshots/BlobForwarder/blob-function-deployed.png)

3. Upload a log file to your blob storage container
4. Verify logs are forwarded successfully by viewing them in New Relic. See [Find and use your data](https://docs.newrelic.com/docs/logs/forward-logs/azure-log-forwarding/#find-data) for instructions on querying your Azure logs
