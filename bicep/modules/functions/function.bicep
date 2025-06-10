@description('Required. Compute type for the deployment. Valid value: "function"')
param computeType string

@description('Required. Name of the App Service Plan')
param servicePlanName string

@description('Required. Deployment mode. Valid values: "production" or "devtest"')
param deploymentMode string

@description('Required. Flag to disable high availability features')
param disableHighAvailability bool

@description('Required. Azure region where resources will be deployed')
param location string

@description('Required. Name of the Function App to be created')
param functionAppName string

@description('Required. Name of the Event Hub that the function will connect to')
param eventHubName string

@description('Required. New Relic License Key for monitoring and observability')
param newRelicLicenseKey string

@description('Required. Flag to control public network access to the Storage Account')
param disablePublicAccessToStorageAccount bool

@description('Optional. Custom attributes to be added to logs')
param logCustomAttributes string

@description('Required. New Relic endpoint for sending data')
param newRelicEndpoint string

@description('Optional. Maximum number of retries for resending logs. Default is 3')
param maxRetriesToResendLogs int = 3

@description('Optional. Interval between retry attempts in milliseconds. Default is 2000')
param retryInterval int = 2000

@description('Required. Name of the Storage Account used by the Function App')
param storageAccountName string

@description('Required. Name of the Event Hub Consumer Group')
param eventHubConsumerGroupName string

@description('Required. Name for the Function App network configuration')
param functionNetworkConfigName string

@description('Required. URL of the Function App deployment package')
param eventHubForwarderFunctionArtifact string

@description('Required. Name of the subnet where the Function App will be deployed')
param functionSubnetName string

@description('Required. Name of the Virtual Network')
param virtualNetworkName string

@description('Required. Event Hub Consumer connection string.')
param ehConsumerKey string

// Variables
var isProduction = (deploymentMode == 'production' ? true : false ) // Defining this to make conditions easier

module asp './asp.bicep' = if (computeType == 'function') {
  name: 'nr-asp-${servicePlanName}'
  params: {
    deploymentMode: deploymentMode
    disablePublicAccessToStorageAccount: disableHighAvailability
    servicePlanName: servicePlanName
    location: location
  }
}

resource storageacc_lookup 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource functionApp 'Microsoft.Web/sites@2020-12-01' = if (computeType == 'function') {
  name: '${functionAppName}-func'
  location: location
  kind: 'functionapp'
  properties: {
    serverFarmId: asp.outputs.resourceId
    siteConfig: {
      appSettings: [
        {
          name: 'EVENTHUB_NAME'
          value: eventHubName
        }
        {
          name: 'EVENTHUB_CONSUMER_CONNECTION'
          value: ehConsumerKey
        }
        {
          name: 'EVENTHUB_CONSUMER_GROUP'
          value: eventHubConsumerGroupName
        }
        {
          name: 'NR_LICENSE_KEY'
          value: newRelicLicenseKey
        }
        {
          name: 'NR_ENDPOINT'
          value: newRelicEndpoint
        }
        {
          name: 'NR_TAGS'
          value: logCustomAttributes
        }
        {
          name: 'NR_MAX_RETRIES'
          value: '${maxRetriesToResendLogs}'
        }
        {
          name: 'NR_RETRY_INTERVAL'
          value: '${retryInterval}'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'node'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~20'
        }
        {
          name: 'NEW_RELIC_LICENSE_KEY'
          value: newRelicLicenseKey
        }
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};AccountKey=${storageacc_lookup.listkeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: (disablePublicAccessToStorageAccount ? eventHubForwarderFunctionArtifact : '0')
        }
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'true'
        }
        
      ]
      alwaysOn: (disablePublicAccessToStorageAccount && !(isProduction)? true : false )
      ftpsState: 'Disabled'
      publicNetworkAccess: (disablePublicAccessToStorageAccount ? 'Disabled' : 'Enabled')
    }
    httpsOnly: true
  }
}

resource functionAppName_ZipDeploy 'Microsoft.Web/sites/extensions@2020-12-01' = if (!disablePublicAccessToStorageAccount) {
  parent: functionApp
  name: 'MSDeploy'
  properties: {
    packageUri: eventHubForwarderFunctionArtifact
  }
}

resource functionNetworkConfig 'Microsoft.Web/sites/networkConfig@2022-03-01' = if (disablePublicAccessToStorageAccount) {
  name: functionNetworkConfigName
  properties: {
    subnetResourceId: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetworkName, functionSubnetName)
    swiftSupported: true
  }
  dependsOn: [
    functionApp
  ]
}
