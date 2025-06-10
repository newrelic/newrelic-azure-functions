@description('Required. Name for the Azure Container Apps Environment')
param acaEnvironmentName string

@description('Required. Azure region where resources will be deployed')
param location string

@description('Optional. Custom attributes to be added to logs')
param logCustomAttributes string

@description('Optional. Flag to disable zone redundancy for the Container Apps Environment')
#disable-next-line no-unused-params
param disableZoneRedundancy bool

@description('Required. Name for the Azure Function App that is deployed')
param functionAppName string

@description('Required. Name of the Storage Account used by the Function App for WebJobs storage.')
param storageAccountName string

@description('Required. New Relic Ingest License Key for publishing the logs and connecting APM.')
param newRelicLicenseKey string

@description('Required. Name of the Event Hub that the function will connect to.')
param eventHubName string

@description('Required. Name of the Event Hub Consumer Group to subscribe to.')
param eventHubConsumerGroupName string

@description('Required. Connection string to read events from the Event Hub consumer group.')
param ehConsumerKey string

@description('Optional. Container image used if ACA option is selected.')
param containerImage string

resource acaEnvironment 'Microsoft.App/managedEnvironments@2024-08-02-preview' = {
  name: acaEnvironmentName
  location: location
  properties: {
    zoneRedundant: false // Move to: disableZoneRedundancy but requires a vnet to be deployed
    workloadProfiles: [
      {
        workloadProfileType: 'Consumption'
        name: 'Consumption'
        enableFips: false
      }
    ]
    peerAuthentication: {
      mtls: {
        enabled: false
      }
    }
    peerTrafficConfiguration: {
      encryption: {
        enabled: false
      }
    }
    publicNetworkAccess: 'Disabled'
  }
}

resource storageacc_lookup 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

// Resource: Azure Function App hosted as a Container App
resource functionAppContainer 'Microsoft.App/containerApps@2023-05-01' = {
  name: substring(functionAppName, 0, 32) // Ensure the name is within Azure's limits
  location: location
  properties: {
    managedEnvironmentId: acaEnvironment.id
    configuration: {
      secrets: [
        {
          name: 'azurewebjobsstorage-accountkey'
          value: storageacc_lookup.listKeys().keys[0].value
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'azure-function-image'
          image: containerImage
          resources: {
            cpu: json('0.5') // Adjust CPU based on your function's needs
            memory: '1.0Gi' // Adjust memory based on your function's needs
          }
          env: [
            // Application settings for Azure Function
            {
              name: 'AzureWebJobsStorage'
              value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};AccountKey=${storageacc_lookup.listkeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
            }
            {
              name: 'FUNCTIONS_EXTENSION_VERSION'
              value: '~4' // Specify your Functions runtime version
            }
            {
              name: 'NR_TAGS'
              value: logCustomAttributes
            }
            {
              name: 'FUNCTIONS_WORKER_RUNTIME'
              value: 'node'
            }
            {
              name: 'NR_LICENSE_KEY'
              value: newRelicLicenseKey
            }
            {
              name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE' // Required for ACA-hosted functions
              value: 'false'
            }
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
          ]
        }
      ]
      // Removed the explicit 'scale.rules' block for Event Hub trigger as platform manages it.
      scale: {
        minReplicas: 0 // Scale down to 0 when no events
        maxReplicas: 20 // Maximum replicas for scaling out
      }
    }
  }
}

output resourceId string = acaEnvironment.id
