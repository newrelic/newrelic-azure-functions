@description('Required. New Relic License Key')
@secure()
param newRelicLicenseKey string

@description('Optional. Name of the existing storage account where VNet Flow Logs PT1H.json files are stored. Must be in the same resource group as this deployment. Leave this blank to create a new storage account (its name will start with \'nrvnetflsrc\').')
param sourceStorageAccountName string = ''

@description('Optional. Event Hub Namespace where VNet Flow Log events will be sent. Leave this blank for a new namespace to be created automatically (its name will start with \'nrvnetflowlogs-ehns-\').')
param eventHubNamespace string = ''

@description('Optional. Event Hub where VNet Flow Log events are sent. Leave this blank for a new Event Hub to be created automatically (its name will be \'nrvnetflowlogs-ehub\').')
param eventHubName string = ''

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

@description('Optional. Disables public network access to the Function and Cursor Storage Accounts (please note that even without enabling this option, access to these Storage Accounts is secured). As a consequence, communication with these Storage Accounts will be performed through a private Virtual Network (VNet). Please note that due to this, the hosting pricing plan for the Function app server farm will need to be upgraded to \'Basic\', as it is the minimum one providing VNet integration for Function apps (you can later upgrade this plan if you require more scaling options). Also note that the following extra resources will be created: a virtual network, two subnets, DNS zone names, virtual network links, and private endpoints. The source storage account (containing VNet flow logs) will remain with its current network configuration.')
param disablePublicAccessToStorageAccount bool = false

var uniqueResourceNameSuffix = uniqueString(resourceGroup().id)
var location_var = (empty(location) ? resourceGroup().location : location)
var createNewSourceStorage = empty(sourceStorageAccountName)
var sourceStorageAccountNameResolved_var = (createNewSourceStorage
  ? 'nrvnetflsrc${uniqueResourceNameSuffix}'
  : sourceStorageAccountName)
var createNewEventHubNamespace = empty(eventHubNamespace)
var createNewEventHub = (empty(eventHubNamespace) || empty(eventHubName))
var eventHubNamespaceName = (createNewEventHubNamespace
  ? 'nrvnetflowlogs-ehns-${uniqueResourceNameSuffix}'
  : eventHubNamespace)
var eventHubName_var = (createNewEventHub ? 'nrvnetflowlogs-ehub' : eventHubName)
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
var privateNetworkASP = {
  kind: 'app'
  properties: {
    name: servicePlanName
    targetWorkerCount: 1
    targetWorkerSizeId: 1
    workerSize: 1
    numberOfWorkers: 1
    computeMode: 'Dynamic'
    zoneRedundant: false
  }
  sku: {
    name: 'B1'
    tier: 'Basic'
    capacity: 1
  }
}
var virtualNetworkName = 'nrvnetflowlogs${uniqueResourceNameSuffix}-vnet'
var functionSubnetName = '${virtualNetworkName}-functions-subnet'
var privateEndpointsSubnetName = '${virtualNetworkName}-private-endpoints-subnet'
var dnsSuffix = environment().suffixes.storage
var privateStorageFileDnsZoneName = 'privatelink.file.${dnsSuffix}'
var privateStorageBlobDnsZoneName = 'privatelink.blob.${dnsSuffix}'
var privateStorageQueueDnsZoneName = 'privatelink.queue.${dnsSuffix}'
var privateStorageTableDnsZoneName = 'privatelink.table.${dnsSuffix}'
var privateStorageFileDnsZoneVirtualNetworkLinkName = '${privateStorageFileDnsZoneName}/${virtualNetworkName}-link'
var privateStorageBlobDnsZoneVirtualNetworkLinkName = '${privateStorageBlobDnsZoneName}/${virtualNetworkName}-link'
var privateStorageQueueDnsZoneVirtualNetworkLinkName = '${privateStorageQueueDnsZoneName}/${virtualNetworkName}-link'
var privateStorageTableDnsZoneVirtualNetworkLinkName = '${privateStorageTableDnsZoneName}/${virtualNetworkName}-link'
var privateEndpointCursorStorageFileName = '${cursorStorageAccountName}-file-pe'
var privateEndpointCursorStorageBlobName = '${cursorStorageAccountName}-blob-pe'
var privateEndpointCursorStorageTableName = '${cursorStorageAccountName}-table-pe'
var privateEndpointCursorStorageQueueName = '${cursorStorageAccountName}-queue-pe'
var privateEndpointFunctionStorageFileName = '${functionStorageAccountName}-file-pe'
var privateEndpointFunctionStorageBlobName = '${functionStorageAccountName}-blob-pe'
var privateEndpointFunctionStorageQueueName = '${functionStorageAccountName}-queue-pe'
var privateEndpointPrivateDnsZoneGroupsCursorStorageFileName = '${privateEndpointCursorStorageFileName}/filePrivateDnsZoneGroup'
var privateEndpointPrivateDnsZoneGroupsCursorStorageBlobName = '${privateEndpointCursorStorageBlobName}/blobPrivateDnsZoneGroup'
var privateEndpointPrivateDnsZoneGroupsCursorStorageTableName = '${privateEndpointCursorStorageTableName}/tablePrivateDnsZoneGroup'
var privateEndpointPrivateDnsZoneGroupsCursorStorageQueueName = '${privateEndpointCursorStorageQueueName}/queuePrivateDnsZoneGroup'
var privateEndpointPrivateDnsZoneGroupsFunctionStorageFileName = '${privateEndpointFunctionStorageFileName}/filePrivateDnsZoneGroup'
var privateEndpointPrivateDnsZoneGroupsFunctionStorageBlobName = '${privateEndpointFunctionStorageBlobName}/blobPrivateDnsZoneGroup'
var privateEndpointPrivateDnsZoneGroupsFunctionStorageQueueName = '${privateEndpointFunctionStorageQueueName}/queuePrivateDnsZoneGroup'
var functionNetworkConfigName = '${functionAppName}/virtualNetwork'
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
var basicScaleConfig = (((scalingMode == 'Basic') && disablePublicAccessToStorageAccount)
  ? privateNetworkASP
  : defaultASP)
var aspConfig = (isHighScaling ? autoscalingASP : basicScaleConfig)

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

resource eventHubNamespaceName_eventHub 'Microsoft.EventHub/namespaces/eventhubs@2021-11-01' = if (createNewEventHub) {
  parent: eventHubNamespace_resource
  name: '${eventHubName_var}'
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
  parent: eventHubNamespace_resource
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

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2022-09-01' = if (disablePublicAccessToStorageAccount) {
  name: virtualNetworkName
  location: location_var
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.2.0.0/16'
      ]
    }
    subnets: [
      {
        name: functionSubnetName
        properties: {
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          delegations: [
            {
              name: 'webapp'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
          addressPrefix: '10.2.0.0/24'
        }
      }
      {
        name: privateEndpointsSubnetName
        properties: {
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          addressPrefix: '10.2.1.0/24'
        }
      }
    ]
  }
}

resource privateStorageFileDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (disablePublicAccessToStorageAccount) {
  name: privateStorageFileDnsZoneName
  location: 'global'
}

resource privateStorageBlobDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (disablePublicAccessToStorageAccount) {
  name: privateStorageBlobDnsZoneName
  location: 'global'
}

resource privateStorageQueueDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (disablePublicAccessToStorageAccount) {
  name: privateStorageQueueDnsZoneName
  location: 'global'
}

resource privateStorageTableDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (disablePublicAccessToStorageAccount) {
  name: privateStorageTableDnsZoneName
  location: 'global'
}

resource privateStorageFileDnsZoneVirtualNetworkLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (disablePublicAccessToStorageAccount) {
  name: privateStorageFileDnsZoneVirtualNetworkLinkName
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
  dependsOn: [
    privateStorageFileDnsZone
  ]
}

resource privateStorageBlobDnsZoneVirtualNetworkLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (disablePublicAccessToStorageAccount) {
  name: privateStorageBlobDnsZoneVirtualNetworkLinkName
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
  dependsOn: [
    privateStorageBlobDnsZone
  ]
}

resource privateStorageQueueDnsZoneVirtualNetworkLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (disablePublicAccessToStorageAccount) {
  name: privateStorageQueueDnsZoneVirtualNetworkLinkName
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
  dependsOn: [
    privateStorageQueueDnsZone
  ]
}

resource privateStorageTableDnsZoneVirtualNetworkLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (disablePublicAccessToStorageAccount) {
  name: privateStorageTableDnsZoneVirtualNetworkLinkName
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
  dependsOn: [
    privateStorageTableDnsZone
  ]
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
    publicNetworkAccess: (disablePublicAccessToStorageAccount ? 'Disabled' : 'Enabled')
    networkAcls: (disablePublicAccessToStorageAccount
      ? json('{"bypass": "None", "defaultAction": "Deny"}')
      : json('{"bypass": "AzureServices", "defaultAction": "Allow"}'))
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
    publicNetworkAccess: (disablePublicAccessToStorageAccount ? 'Disabled' : 'Enabled')
    networkAcls: (disablePublicAccessToStorageAccount
      ? json('{"bypass": "None", "defaultAction": "Deny"}')
      : json('{"bypass": "AzureServices", "defaultAction": "Allow"}'))
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

resource privateEndpointCursorStorageFile 'Microsoft.Network/privateEndpoints@2022-05-01' = if (disablePublicAccessToStorageAccount) {
  name: privateEndpointCursorStorageFileName
  location: location_var
  properties: {
    subnet: {
      id: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetworkName, privateEndpointsSubnetName)
    }
    privateLinkServiceConnections: [
      {
        name: 'CursorStorageFilePrivateLinkConnection'
        properties: {
          privateLinkServiceId: cursorStorageAccount.id
          groupIds: [
            'file'
          ]
        }
      }
    ]
  }
  dependsOn: [
    virtualNetwork
  ]
}

resource privateEndpointCursorStorageBlob 'Microsoft.Network/privateEndpoints@2022-05-01' = if (disablePublicAccessToStorageAccount) {
  name: privateEndpointCursorStorageBlobName
  location: location_var
  properties: {
    subnet: {
      id: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetworkName, privateEndpointsSubnetName)
    }
    privateLinkServiceConnections: [
      {
        name: 'CursorStorageBlobPrivateLinkConnection'
        properties: {
          privateLinkServiceId: cursorStorageAccount.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
  dependsOn: [
    virtualNetwork
  ]
}

resource privateEndpointCursorStorageTable 'Microsoft.Network/privateEndpoints@2022-05-01' = if (disablePublicAccessToStorageAccount) {
  name: privateEndpointCursorStorageTableName
  location: location_var
  properties: {
    subnet: {
      id: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetworkName, privateEndpointsSubnetName)
    }
    privateLinkServiceConnections: [
      {
        name: 'CursorStorageTablePrivateLinkConnection'
        properties: {
          privateLinkServiceId: cursorStorageAccount.id
          groupIds: [
            'table'
          ]
        }
      }
    ]
  }
  dependsOn: [
    virtualNetwork
  ]
}

resource privateEndpointCursorStorageQueue 'Microsoft.Network/privateEndpoints@2022-05-01' = if (disablePublicAccessToStorageAccount) {
  name: privateEndpointCursorStorageQueueName
  location: location_var
  properties: {
    subnet: {
      id: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetworkName, privateEndpointsSubnetName)
    }
    privateLinkServiceConnections: [
      {
        name: 'CursorStorageQueuePrivateLinkConnection'
        properties: {
          privateLinkServiceId: cursorStorageAccount.id
          groupIds: [
            'queue'
          ]
        }
      }
    ]
  }
  dependsOn: [
    virtualNetwork
  ]
}

resource privateEndpointFunctionStorageFile 'Microsoft.Network/privateEndpoints@2022-05-01' = if (disablePublicAccessToStorageAccount) {
  name: privateEndpointFunctionStorageFileName
  location: location_var
  properties: {
    subnet: {
      id: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetworkName, privateEndpointsSubnetName)
    }
    privateLinkServiceConnections: [
      {
        name: 'FunctionStorageFilePrivateLinkConnection'
        properties: {
          privateLinkServiceId: functionStorageAccount.id
          groupIds: [
            'file'
          ]
        }
      }
    ]
  }
  dependsOn: [
    virtualNetwork
  ]
}

resource privateEndpointFunctionStorageBlob 'Microsoft.Network/privateEndpoints@2022-05-01' = if (disablePublicAccessToStorageAccount) {
  name: privateEndpointFunctionStorageBlobName
  location: location_var
  properties: {
    subnet: {
      id: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetworkName, privateEndpointsSubnetName)
    }
    privateLinkServiceConnections: [
      {
        name: 'FunctionStorageBlobPrivateLinkConnection'
        properties: {
          privateLinkServiceId: functionStorageAccount.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
  dependsOn: [
    virtualNetwork
  ]
}

resource privateEndpointFunctionStorageQueue 'Microsoft.Network/privateEndpoints@2022-05-01' = if (disablePublicAccessToStorageAccount) {
  name: privateEndpointFunctionStorageQueueName
  location: location_var
  properties: {
    subnet: {
      id: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetworkName, privateEndpointsSubnetName)
    }
    privateLinkServiceConnections: [
      {
        name: 'FunctionStorageQueuePrivateLinkConnection'
        properties: {
          privateLinkServiceId: functionStorageAccount.id
          groupIds: [
            'queue'
          ]
        }
      }
    ]
  }
  dependsOn: [
    virtualNetwork
  ]
}

resource privateEndpointPrivateDnsZoneGroupsCursorStorageFile 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-05-01' = if (disablePublicAccessToStorageAccount) {
  name: privateEndpointPrivateDnsZoneGroupsCursorStorageFileName
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config'
        properties: {
          privateDnsZoneId: privateStorageFileDnsZone.id
        }
      }
    ]
  }
  dependsOn: [
    privateEndpointCursorStorageFile
  ]
}

resource privateEndpointPrivateDnsZoneGroupsCursorStorageBlob 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-05-01' = if (disablePublicAccessToStorageAccount) {
  name: privateEndpointPrivateDnsZoneGroupsCursorStorageBlobName
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config'
        properties: {
          privateDnsZoneId: privateStorageBlobDnsZone.id
        }
      }
    ]
  }
  dependsOn: [
    privateEndpointCursorStorageBlob
  ]
}

resource privateEndpointPrivateDnsZoneGroupsCursorStorageTable 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-05-01' = if (disablePublicAccessToStorageAccount) {
  name: privateEndpointPrivateDnsZoneGroupsCursorStorageTableName
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config'
        properties: {
          privateDnsZoneId: privateStorageTableDnsZone.id
        }
      }
    ]
  }
  dependsOn: [
    privateEndpointCursorStorageTable
  ]
}

resource privateEndpointPrivateDnsZoneGroupsCursorStorageQueue 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-05-01' = if (disablePublicAccessToStorageAccount) {
  name: privateEndpointPrivateDnsZoneGroupsCursorStorageQueueName
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config'
        properties: {
          privateDnsZoneId: privateStorageQueueDnsZone.id
        }
      }
    ]
  }
  dependsOn: [
    privateEndpointCursorStorageQueue
  ]
}

resource privateEndpointPrivateDnsZoneGroupsFunctionStorageFile 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-05-01' = if (disablePublicAccessToStorageAccount) {
  name: privateEndpointPrivateDnsZoneGroupsFunctionStorageFileName
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config'
        properties: {
          privateDnsZoneId: privateStorageFileDnsZone.id
        }
      }
    ]
  }
  dependsOn: [
    privateEndpointFunctionStorageFile
  ]
}

resource privateEndpointPrivateDnsZoneGroupsFunctionStorageBlob 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-05-01' = if (disablePublicAccessToStorageAccount) {
  name: privateEndpointPrivateDnsZoneGroupsFunctionStorageBlobName
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config'
        properties: {
          privateDnsZoneId: privateStorageBlobDnsZone.id
        }
      }
    ]
  }
  dependsOn: [
    privateEndpointFunctionStorageBlob
  ]
}

resource privateEndpointPrivateDnsZoneGroupsFunctionStorageQueue 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-05-01' = if (disablePublicAccessToStorageAccount) {
  name: privateEndpointPrivateDnsZoneGroupsFunctionStorageQueueName
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config'
        properties: {
          privateDnsZoneId: privateStorageQueueDnsZone.id
        }
      }
    ]
  }
  dependsOn: [
    privateEndpointFunctionStorageQueue
  ]
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
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${functionStorageAccountName};AccountKey=${listKeys(functionStorageAccount.id,'2021-09-01').keys[0].value};EndpointSuffix=core.windows.net'
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
          value: (disablePublicAccessToStorageAccount ? vnetFlowLogsForwarderFunctionArtifact : '0')
        }
      ]
      alwaysOn: disablePublicAccessToStorageAccount
      ftpsState: 'Disabled'
      publicNetworkAccess: (disablePublicAccessToStorageAccount ? 'Disabled' : 'Enabled')
    }
  }
  dependsOn: [
    cursorStorageAccountName_default_cursorTable

    (disablePublicAccessToStorageAccount
      ? resourceId(
          'Microsoft.Network/privateEndpoints/privateDnsZoneGroups',
          privateEndpointCursorStorageBlobName,
          'blobPrivateDnsZoneGroup'
        )
      : cursorStorageAccount.id)
    (disablePublicAccessToStorageAccount
      ? resourceId(
          'Microsoft.Network/privateEndpoints/privateDnsZoneGroups',
          privateEndpointCursorStorageFileName,
          'filePrivateDnsZoneGroup'
        )
      : cursorStorageAccount.id)
    (disablePublicAccessToStorageAccount
      ? resourceId(
          'Microsoft.Network/privateEndpoints/privateDnsZoneGroups',
          privateEndpointCursorStorageTableName,
          'tablePrivateDnsZoneGroup'
        )
      : cursorStorageAccount.id)
    (disablePublicAccessToStorageAccount
      ? resourceId(
          'Microsoft.Network/privateEndpoints/privateDnsZoneGroups',
          privateEndpointCursorStorageQueueName,
          'queuePrivateDnsZoneGroup'
        )
      : cursorStorageAccount.id)
    (disablePublicAccessToStorageAccount
      ? resourceId(
          'Microsoft.Network/privateEndpoints/privateDnsZoneGroups',
          privateEndpointFunctionStorageBlobName,
          'blobPrivateDnsZoneGroup'
        )
      : functionStorageAccount.id)
    (disablePublicAccessToStorageAccount
      ? resourceId(
          'Microsoft.Network/privateEndpoints/privateDnsZoneGroups',
          privateEndpointFunctionStorageFileName,
          'filePrivateDnsZoneGroup'
        )
      : functionStorageAccount.id)
    (disablePublicAccessToStorageAccount
      ? resourceId(
          'Microsoft.Network/privateEndpoints/privateDnsZoneGroups',
          privateEndpointFunctionStorageQueueName,
          'queuePrivateDnsZoneGroup'
        )
      : functionStorageAccount.id)
    (disablePublicAccessToStorageAccount
      ? resourceId(
          'Microsoft.Network/privateDnsZones/virtualNetworkLinks',
          privateStorageBlobDnsZoneName,
          '${virtualNetworkName}-link'
        )
      : cursorStorageAccount.id)
    (disablePublicAccessToStorageAccount
      ? resourceId(
          'Microsoft.Network/privateDnsZones/virtualNetworkLinks',
          privateStorageFileDnsZoneName,
          '${virtualNetworkName}-link'
        )
      : cursorStorageAccount.id)
    (disablePublicAccessToStorageAccount
      ? resourceId(
          'Microsoft.Network/privateDnsZones/virtualNetworkLinks',
          privateStorageQueueDnsZoneName,
          '${virtualNetworkName}-link'
        )
      : cursorStorageAccount.id)
    (disablePublicAccessToStorageAccount
      ? resourceId(
          'Microsoft.Network/privateDnsZones/virtualNetworkLinks',
          privateStorageTableDnsZoneName,
          '${virtualNetworkName}-link'
        )
      : cursorStorageAccount.id)
  ]
}

resource functionAppName_MSDeploy 'Microsoft.Web/sites/extensions@2020-12-01' = if (!disablePublicAccessToStorageAccount) {
  parent: functionApp
  name: 'MSDeploy'
  properties: {
    packageUri: vnetFlowLogsForwarderFunctionArtifact
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
    virtualNetwork
  ]
}

@description('Storage account name to configure Network Watcher to use for VNet Flow Logs. Container name should be \'insights-logs-flowlogflowevent\'.')
output sourceStorageAccountName string = sourceStorageAccountNameResolved_var
output functionAppName string = functionAppName
output eventHubNamespace string = eventHubNamespaceName
output eventHubName string = eventHubName_var
output cursorStorageAccountName string = cursorStorageAccountName
output eventGridSystemTopicName string = eventGridSystemTopicName_var
