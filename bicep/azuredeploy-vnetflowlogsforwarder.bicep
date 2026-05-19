@description('Required. New Relic License Key')
@secure()
param newRelicLicenseKey string

@description('Optional. Name of the existing storage account where VNet Flow Logs PT1H.json files are stored. Must be in the same resource group as this deployment. Leave this blank to create a new storage account (its name will start with \'nrvnetflsrc\').')
param sourceStorageAccountName string = ''

@description('Optional. Name for the Event Grid System Topic that will be created to monitor blob events from the source storage account. Leave this blank to auto-generate a unique name (its name will start with \'nrvnetflowlogs-egtopic-\').')
param eventGridSystemTopicName string = ''

@description('Optional. Name for the Event Grid Subscription that will be created to filter PT1H.json files. Leave this blank to auto-generate a unique name (its name will start with \'nrvnetflowlogs-egsub-\').')
param eventGridSubscriptionName string = ''

@description('Optional. Region where all resources included in this template will be deployed. Leave this blank to use the same region as the one of the resource group.')
param location string = ''

@description('Optional. The Logs API endpoint used to send your logs to. By default, it is https://log-api.newrelic.com/log/v1 if your account is in the United States (US) region. If you\'re in the European Union (EU) region, use https://log-api.eu.newrelic.com/log/v1. If you\'re in the Japan (JP) region, use https://log-api.jp.newrelic.com/log/v1')
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
  ? 'nrvnetflsrc${uniqueResourceNameSuffix}'
  : sourceStorageAccountName)
var eventHubNamespaceName = 'nrvnetflowlogs-ehns-${uniqueResourceNameSuffix}'
var eventHubName = 'nrvnetflowlogs-ehub'
var eventHubConsumerGroupName = 'nrvnetflowlogs-cg'
var eventHubAuthRuleName = 'nrvnetflowlogs-auth'
var eventGridSystemTopicName_var = (empty(eventGridSystemTopicName)
  ? 'nrvnetflowlogs-egtopic-${uniqueResourceNameSuffix}'
  : eventGridSystemTopicName)
var eventGridSubscriptionName_var = (empty(eventGridSubscriptionName)
  ? 'nrvnetflowlogs-egsub-${uniqueResourceNameSuffix}'
  : eventGridSubscriptionName)
var cursorStorageAccountName = 'nrvnetflcur${uniqueResourceNameSuffix}'
var cursorTableName = 'nrvnetflowlogscursors'
var functionStorageAccountName = 'nrvnetflfn${uniqueResourceNameSuffix}'
var servicePlanName = 'nrvnetflowlogs-asp-${uniqueResourceNameSuffix}'
var functionAppName = 'nrvnetflowlogs-func-${uniqueResourceNameSuffix}'
var sourceStorageAccountId = sourceStorageAccountNameResolved.id
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

resource eventHubNamespace 'Microsoft.EventHub/namespaces@2021-11-01' = {
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

resource eventHubNamespaceName_eventHub 'Microsoft.EventHub/namespaces/eventhubs@2021-11-01' = {
  parent: eventHubNamespace
  name: '${eventHubName}'
  location: location_var
  properties: {
    messageRetentionInDays: 1
    partitionCount: ((scalingMode == 'Enterprise') ? 32 : 4)
  }
}

resource eventHubNamespaceName_eventHubName_eventHubConsumerGroup 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2021-11-01' = {
  parent: eventHubNamespaceName_eventHub
  name: eventHubConsumerGroupName
  properties: {}
}

resource eventHubNamespaceName_eventHubAuthRule 'Microsoft.EventHub/namespaces/AuthorizationRules@2021-11-01' = {
  parent: eventHubNamespace
  name: '${eventHubAuthRuleName}'
  properties: {
    rights: [
      'Listen'
      'Send'
    ]
  }
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
        resourceId: eventHubNamespaceName_eventHub.id
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

resource cursorStorageAccountName_default 'Microsoft.Storage/storageAccounts/tableServices@2022-09-01' = {
  parent: cursorStorageAccount
  name: 'default'
  properties: {}
}

resource cursorStorageAccountName_default_cursorTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2022-09-01' = {
  parent: cursorStorageAccountName_default
  name: cursorTableName
  properties: {}
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
          value: eventHubName
        }
        {
          name: 'EVENTHUB_CONSUMER_CONNECTION'
          value: listKeys(eventHubNamespaceName_eventHubAuthRule.id, '2021-11-01').primaryConnectionString
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
          value: 'DefaultEndpointsProtocol=https;AccountName=${sourceStorageAccountNameResolved_var};AccountKey=${listKeys(sourceStorageAccountNameResolved.id,'2021-09-01').keys[0].value};EndpointSuffix=core.windows.net'
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
    cursorStorageAccountName_default_cursorTable
  ]
}

resource functionAppName_MSDeploy 'Microsoft.Web/sites/extensions@2020-12-01' = {
  parent: functionApp
  name: 'MSDeploy'
  properties: {
    packageUri: vnetFlowLogsForwarderFunctionArtifact
  }
}

@description('Storage account name to configure Network Watcher to use for VNet Flow Logs. Container name should be \'insights-logs-flowlogflowevent\'.')
output sourceStorageAccountName string = sourceStorageAccountNameResolved_var
output functionAppName string = functionAppName
output eventHubNamespace string = eventHubNamespaceName
output eventHubName string = eventHubName
output cursorStorageAccountName string = cursorStorageAccountName
output eventGridSystemTopicName string = eventGridSystemTopicName_var
