@description('Required. New Relic License Key')
param newRelicLicenseKey string

@description('Optional. Name of the existing storage account where VNet Flow Logs PT1H.json files are stored. Must be in the same resource group as this deployment. Leave this blank to create a new storage account (its name will start with \'nrvnetsrc\').')
param sourceStorageAccountName string = ''

@description('Optional. Event Hub Namespace where VNet Flow Log events will be sent. Leave this blank for a new namespace to be created automatically (its name will start with \'nrvnetflowlogs-\').')
param eventHubNamespace string = ''

@description('Optional. Event Hub where VNet Flow Log events are sent. Leave this blank for a new Event Hub to be created automatically (its name will be \'nrvnetflowlogs\').')
param eventHubName string = ''

@description('Optional. Name for the Event Grid System Topic that will be created to monitor blob events from the source storage account. Leave this blank to auto-generate a unique name (will start with \'nrvnetflowlogs-egtopic-\').')
param eventGridSystemTopicName string = ''

@description('Optional. Name for the Event Grid Subscription that will be created to filter PT1H.json files. Leave this blank to auto-generate a unique name (will start with \'nrvnetflowlogs-egsub-\').')
param eventGridSubscriptionName string = ''

@description('Optional. Region where all resources included in this template will be deployed. Leave this blank to use the same region as the one of the resource group.')
param location string = ''

@description('Optional. The Logs API endpoint used to send your logs to. By default, it is https://log-api.newrelic.com/log/v1 if your account is in the United States (US) region. Otherwise, if you\'re in the European Union (EU) region, you should use https://log-api.eu.newrelic.com/log/v1')
param newRelicEndpoint string = 'https://log-api.newrelic.com/log/v1'

@description('Optional. The scaling for the resources. If set to \'Enterprise\', the Function app will be deployed in a Premium Function App Service Plan (with Scaling), otherwise it will be deployed in a Basic/Dynamic App Service Plan.')
@allowed([
  'Basic'
  'Enterprise'
])
param scalingMode string = 'Basic'

var uniqueResourceNameSuffix = uniqueString(resourceGroup().id)
var location_var = (empty(location) ? resourceGroup().location : location)
var createNewSourceStorage = empty(sourceStorageAccountName)
var sourceStorageAccountNameResolved_var = (createNewSourceStorage
  ? 'nrvnetsrc${uniqueResourceNameSuffix}'
  : sourceStorageAccountName)
var createNewEventHubNamespace = empty(eventHubNamespace)
var createNewEventHub = (empty(eventHubNamespace) || empty(eventHubName))
var eventHubNamespaceName = (createNewEventHubNamespace
  ? 'nrvnetflowlogs-${uniqueResourceNameSuffix}'
  : eventHubNamespace)
var eventHubName_var = (createNewEventHub ? 'nrvnetflowlogs' : eventHubName)
var eventHubConsumerGroupName = 'nrvnetflowlogs'
var eventHubAuthRuleName = 'nrvnetflowlogs-auth-rule'
var eventGridSystemTopicName_var = (empty(eventGridSystemTopicName)
  ? 'nrvnetflowlogs-egtopic-${uniqueResourceNameSuffix}'
  : eventGridSystemTopicName)
var eventGridSubscriptionName_var = (empty(eventGridSubscriptionName)
  ? 'nrvnetflowlogs-egsub-${uniqueResourceNameSuffix}'
  : eventGridSubscriptionName)
var cursorStorageAccountName = 'nrvnetcur${uniqueResourceNameSuffix}'
var cursorTableName = 'vnetflowlogcursors'
var functionStorageAccountName = 'nrvnetfunc${uniqueResourceNameSuffix}'
var servicePlanName = 'nrvnetflowlogs-asp-${uniqueResourceNameSuffix}'
var functionAppName = 'nrvnetflowlogs-func-${uniqueResourceNameSuffix}'
var sourceStorageAccountId = createNewSourceStorage ? sourceStorageAccountNameResolved.id : existingSourceStorage.id
var vnetFlowLogsForwarderFunctionArtifact = 'https://github.com/newrelic/newrelic-azure-functions/releases/latest/download/LogForwarder.zip'
var autoscalingASP = {
  kind: 'elastic'
  properties: {
    perSiteScaling: true
    elasticScaleEnabled: true
    maximumElasticWorkerCount: 20
    zoneRedundant: false
  }
  sku: {
    name: 'EP1'
    tier: 'ElasticPremium'
    size: 'EP1'
    family: 'EP'
    capacity: 1
  }
}
var defaultASP = {
  kind: 'functionapp'
  properties: {
    name: servicePlanName
    targetWorkerCount: 1
    targetWorkerSizeId: 1
    workerSize: '1'
    numberOfWorkers: 1
    computeMode: 'Dynamic'
  }
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
}
var isHighScaling = ((scalingMode == 'Enterprise') ? true : false)
var aspConfig = (isHighScaling ? autoscalingASP : defaultASP)

resource sourceStorageAccountNameResolved 'Microsoft.Storage/storageAccounts@2021-09-01' = if (createNewSourceStorage) {
  name: sourceStorageAccountNameResolved_var
  location: location_var
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: true
    encryption: {
      services: {
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    accessTier: 'Hot'
  }
}

resource existingSourceStorage 'Microsoft.Storage/storageAccounts@2021-09-01' existing = if (!createNewSourceStorage) {
  name: sourceStorageAccountName
}

resource eventHubNamespace_resource 'Microsoft.EventHub/namespaces@2021-11-01' = if (createNewEventHubNamespace) {
  name: eventHubNamespaceName
  location: location_var
  sku: {
    name: 'Standard'
    tier: 'Standard'
    capacity: 1
  }
  properties: {
    minimumTlsVersion: '1.2'
    isAutoInflateEnabled: ((scalingMode == 'Enterprise') ? true : false)
    maximumThroughputUnits: ((scalingMode == 'Enterprise') ? 40 : 0)
    zoneRedundant: false
  }
}

resource existingEventHubNamespace 'Microsoft.EventHub/namespaces@2021-11-01' existing = if (!createNewEventHubNamespace) {
  name: eventHubNamespace
}

resource eventHubNamespaceName_eventHub 'Microsoft.EventHub/namespaces/eventhubs@2021-11-01' = if (createNewEventHub) {
  name: '${eventHubNamespaceName}/${eventHubName_var}'
  location: location_var
  properties: {
    messageRetentionInDays: 1
    partitionCount: ((scalingMode == 'Enterprise') ? 32 : 4)
  }
  dependsOn: [
    eventHubNamespace_resource
  ]
}

resource existingEventHub 'Microsoft.EventHub/namespaces/eventhubs@2021-11-01' existing = if (!createNewEventHub) {
  name: '${eventHubNamespaceName}/${eventHubName}'
}

resource eventHubNamespaceName_eventHubName_eventHubConsumerGroup 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2021-11-01' = {
  name: '${eventHubNamespaceName}/${eventHubName_var}/${eventHubConsumerGroupName}'
  properties: {}
  dependsOn: [
    eventHubNamespaceName_eventHub
  ]
}

resource eventHubNamespaceName_eventHubAuthRule 'Microsoft.EventHub/namespaces/AuthorizationRules@2021-11-01' = {
  name: '${eventHubNamespaceName}/${eventHubAuthRuleName}'
  properties: {
    rights: [
      'Listen'
      'Send'
    ]
  }
  dependsOn: [
    eventHubNamespace_resource
  ]
}

resource eventGridSystemTopic 'Microsoft.EventGrid/systemTopics@2021-12-01' = {
  name: eventGridSystemTopicName_var
  location: location_var
  properties: {
    source: sourceStorageAccountId
    topicType: 'Microsoft.Storage.StorageAccounts'
  }
}

resource eventGridSystemTopicName_eventGridSubscription 'Microsoft.EventGrid/systemTopics/eventSubscriptions@2021-12-01' = {
  parent: eventGridSystemTopic
  name: '${eventGridSubscriptionName_var}'
  properties: {
    destination: {
      endpointType: 'EventHub'
      properties: {
        resourceId: createNewEventHub ? eventHubNamespaceName_eventHub.id : existingEventHub.id
      }
    }
    filter: {
      includedEventTypes: [
        'Microsoft.Storage.BlobCreated'
      ]
      enableAdvancedFilteringOnArrays: true
      advancedFilters: [
        {
          operatorType: 'StringContains'
          key: 'subject'
          values: [
            'insights-logs-flowlogflowevent'
          ]
        }
      ]
      subjectEndsWith: 'PT1H.json'
    }
    labels: []
    eventDeliverySchema: 'EventGridSchema'
    retryPolicy: {
      maxDeliveryAttempts: 30
      eventTimeToLiveInMinutes: 1440
    }
  }
}

resource cursorStorageAccount 'Microsoft.Storage/storageAccounts@2021-09-01' = {
  name: cursorStorageAccountName
  location: location_var
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: true
    encryption: {
      services: {
        table: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    accessTier: 'Hot'
  }
}

resource functionStorageAccount 'Microsoft.Storage/storageAccounts@2021-09-01' = {
  name: functionStorageAccountName
  location: location_var
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: true
    encryption: {
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    accessTier: 'Hot'
  }
}

resource servicePlan 'Microsoft.Web/serverfarms@2021-03-01' = {
  name: servicePlanName
  location: location_var
  kind: aspConfig.kind
  properties: aspConfig.properties
  sku: aspConfig.sku
}

resource functionApp 'Microsoft.Web/sites@2021-03-01' = {
  name: functionAppName
  location: location_var
  kind: 'functionapp'
  properties: {
    serverFarmId: servicePlan.id
    httpsOnly: true
    siteConfig: {
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${functionStorageAccountName};AccountKey=${listKeys(functionStorageAccount.id,'2021-09-01').keys[0].value};EndpointSuffix=core.windows.net'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${functionStorageAccountName};AccountKey=${listKeys(functionStorageAccount.id,'2021-09-01').keys[0].value};EndpointSuffix=core.windows.net'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(functionAppName)
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
          value: '~22'
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '0'
        }
        {
          name: 'VNETFLOWLOGS_FORWARDER_ENABLED'
          value: 'true'
        }
        {
          name: 'EVENTHUB_NAME'
          value: eventHubName_var
        }
        {
          name: 'EVENTHUB_CONSUMER_CONNECTION'
          value: listKeys(resourceId('Microsoft.EventHub/namespaces/authorizationRules', eventHubNamespaceName, eventHubAuthRuleName), '2021-11-01').primaryConnectionString
        }
        {
          name: 'EVENTHUB_CONSUMER_GROUP'
          value: eventHubConsumerGroupName
        }
        {
          name: 'SOURCE_STORAGE_ACCOUNT_NAME'
          value: sourceStorageAccountNameResolved_var
        }
        {
          name: 'SOURCE_STORAGE_CONNECTION'
          value: 'DefaultEndpointsProtocol=https;AccountName=${sourceStorageAccountNameResolved_var};AccountKey=${listKeys(sourceStorageAccountId,'2021-09-01').keys[0].value};EndpointSuffix=core.windows.net'
        }
        {
          name: 'CURSOR_STORAGE_CONNECTION'
          value: 'DefaultEndpointsProtocol=https;AccountName=${cursorStorageAccountName};AccountKey=${listKeys(cursorStorageAccount.id,'2021-09-01').keys[0].value};EndpointSuffix=core.windows.net'
        }
        {
          name: 'CURSOR_TABLE_NAME'
          value: cursorTableName
        }
        {
          name: 'NR_LICENSE_KEY'
          value: newRelicLicenseKey
        }
        {
          name: 'NR_ENDPOINT'
          value: newRelicEndpoint
        }
      ]
    }
  }
  dependsOn: [
    eventHubNamespaceName_eventHubAuthRule
  ]
}

resource functionAppName_ZipDeploy 'Microsoft.Web/sites/extensions@2020-12-01' = {
  parent: functionApp
  name: 'ZipDeploy'
  properties: {
    packageUri: vnetFlowLogsForwarderFunctionArtifact
  }
}

@description('Storage account name to configure Network Watcher to use for VNet Flow Logs. Container name should be \'insights-logs-flowlogflowevent\'.')
output sourceStorageAccountName string = sourceStorageAccountNameResolved_var
output functionAppName string = functionAppName
output eventHubNamespace string = eventHubNamespaceName
output eventHubName string = eventHubName_var
output cursorStorageAccountName string = cursorStorageAccountName
output eventGridSystemTopicName string = eventGridSystemTopicName_var
