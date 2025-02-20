@description('Required. New Relic License Key')
param newRelicLicenseKey string

@description('Optional. Event Hub Namespace where all logs to be forwarded to New Relic are being sent to. Leave this blank for a new namespace to be created automatically (its name will start with \'nrlogs-\').')
param eventHubNamespace string = ''

@description('Optional. Event Hub where all the Azure Platform logs are being sent to in order to be forwarded to New Relic. Leave this blank for a new Event Hub to be created automatically (its name will be \'nrlogs\').')
param eventHubName string = ''

@description('Required. Region where all resources included in this template will be deployed. Leave this blank to use the same region as the one of the resource group.')
param location string

@allowed([
  'devtest'
  'production'
])
@description('Optional. Used to determine if the Azure resources will be provisioned in a High Availability mode. Zone Redundancy is an immutable field on App Service Plans. So this will require a redeploy if you toggle between.')
param deploymentMode string = 'devtest'

@description('Optional. The Logs API endpoint used to send your logs to. By default, it is https://log-api.newrelic.com/log/v1 if your account is in the United States (US) region. Otherwise, if you\'re in the European Union (EU) region, you should use https://log-api.eu.newrelic.com/log/v1')
@allowed([
  'https://log-api.newrelic.com/log/v1'
  'https://log-api.eu.newrelic.com/log/v1'

])
param newRelicEndpoint string = 'https://log-api.newrelic.com/log/v1'

@description('Optional. List of semicolon-separated custom attributes that you would like to enrich the forwarded logs with. This can be useful, for example, if you want to indicate common attributes shared by all the logs collected in this account, such as: \'environment:production;department:sales;country:Germany\'')
param logCustomAttributes string = 'azure-forwarded'

@description('Optional. Maximum number of attempts the forwarder function will perform in the event of a failure while sending your data.')
@minValue(1)
param maxRetriesToResendLogs int = 3

@description('Optional. Number of milliseconds to wait between consecutive retries to send the logs.')
@minValue(100)
param retryInterval int = 2000

@description('Optional. Contains the record of all create, update, delete, and action operations performed through Resource Manager. Examples of Administrative events include create virtual machine and delete network security group. Every action taken by a user or application using Resource Manager is modeled as an operation on a particular resource type. If the operation type is Write, Delete, or Action, the records of both the start and success or fail of that operation are recorded in the Administrative category. Administrative events also include any changes to Azure role-based access control in a subscription.')
param forwardAdministrativeAzureActivityLogs bool = false

@description('Optional. Contains the record of activations for Azure alerts. An example of an Alert event is CPU % on myVM has been over 80 for the past 5 minutes.')
param forwardAlertAzureActivityLogs bool = false

@description('Optional. Contains the record of any events related to the operation of the autoscale engine based on any autoscale settings you have defined in your subscription. An example of an Autoscale event is Autoscale scale up action failed.')
param forwardAutoscaleAzureActivityLogs bool = false

@description('Optional. Contains records of all effect action operations performed by Azure Policy. Examples of Policy events include Audit and Deny. Every action taken by Policy is modeled as an operation on a resource.')
param forwardPolicyAzureActivityLogs bool = false

@description('Optional. Contains recommendation events from Azure Advisor.')
param forwardRecommendationAzureActivityLogs bool = false

@description('Optional. Contains the record of any resource health events that have occurred to your Azure resources. An example of a Resource Health event is Virtual Machine health status changed to unavailable. Resource Health events can represent one of four health statuses: Available, Unavailable, Degraded, and Unknown. Additionally, Resource Health events can be categorized as being Platform Initiated or User Initiated.')
param forwardResourceHealthAzureActivityLogs bool = false

@description('Optional. Contains the record of any alerts generated by Azure Security Center. An example of a Security event is Suspicious double extension file executed.')
param forwardSecurityAzureActivityLogs bool = false

@description('Optional. Contains the record of any service health incidents that have occurred in Azure. An example of a Service Health event SQL Azure in East US is experiencing downtime. Service Health events come in Six varieties: Action Required, Assisted Recovery, Incident, Maintenance, Information, or Security. These events are only created if you have a resource in the subscription that would be impacted by the event.')
param forwardServiceHealthAzureActivityLogs bool = false

@description('Optional. Disables public network access to the Storage Account (please note that even without enabling this option, access to the Storage Account is secured). As a consequence, communication with the Service Account will be performed through a private Virtual Network (VNet). Please note that due to this, the hosting pricing plan for the Function app server farm will need to be upgraded to \'Basic\', as it is the minimum one providing VNet integration for Function apps (you can later upgrade this plan if you require more scaling options). Also note that the following extra resources will be created: a virtual network, a subnet, DNS zone names, virtual network links, private endpoints and a Storage Account file share.')
param disablePublicAccessToStorageAccount bool = true

var onePerResourceGroupUniqueSuffix = uniqueString(resourceGroup().id)
var createNewEventHubNamespace = (eventHubNamespace == '')
var eventHubNamespaceName = (createNewEventHubNamespace
  ? 'nrlogs-eventhub-namespace-${onePerResourceGroupUniqueSuffix}'
  : eventHubNamespace)
var createNewEventHub = (eventHubName == '')
var eventHub_name = (createNewEventHub ? 'nrlogs-eventhub' : eventHubName)
var eventHubConsumerGroupName = 'nrlogs-consumergroup'
var logConsumerAuthorizationRuleName = 'nrlogs-consumer-policy'
var logProducerAuthorizationRuleName = 'nrlogs-producer-policy'
var storageAccountName = 'nrlogs${onePerResourceGroupUniqueSuffix}'
var servicePlanName = 'nrlogs-serviceplan-${onePerResourceGroupUniqueSuffix}'
var onePerResourceGroupAndEventHubUniqueSuffix = uniqueString(
  resourceGroup().id,
  eventHubNamespaceName,
  eventHub_name
)
var functionAppName = 'nrlogs-eventhubforwarder-${onePerResourceGroupAndEventHubUniqueSuffix}'
var activityLogsDiagnosticSettingName = 'nrlogs-activity-log-diagnostic-setting-${onePerResourceGroupAndEventHubUniqueSuffix}'
var createActivityLogsDiagnosticSetting = (forwardAdministrativeAzureActivityLogs || forwardAlertAzureActivityLogs || forwardAutoscaleAzureActivityLogs || forwardPolicyAzureActivityLogs || forwardRecommendationAzureActivityLogs || forwardResourceHealthAzureActivityLogs || forwardSecurityAzureActivityLogs || forwardServiceHealthAzureActivityLogs)
var eventHubForwarderFunctionArtifact = 'https://github.com/newrelic/newrelic-azure-functions/releases/latest/download/EventHubForwarder.zip'
var virtualNetworkName = 'nrlogs${onePerResourceGroupUniqueSuffix}-virtual-network'
var functionSubnetName = '${virtualNetworkName}-internal-functions-subnet'
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
var privateEndpointStorageFileName = '${storageAccountName}-file-private-endpoint'
var privateEndpointStorageTableName = '${storageAccountName}-table-private-endpoint'
var privateEndpointStorageBlobName = '${storageAccountName}-blob-private-endpoint'
var privateEndpointStorageQueueName = '${storageAccountName}-queue-private-endpoint'
var privateEndpointPrivateDnsZoneGroupsStorageFileName = '${privateEndpointStorageFileName}/filePrivateDnsZoneGroup'
var privateEndpointPrivateDnsZoneGroupsStorageBlobName = '${privateEndpointStorageBlobName}/blobPrivateDnsZoneGroup'
var privateEndpointPrivateDnsZoneGroupsStorageTableName = '${privateEndpointStorageTableName}/tablePrivateDnsZoneGroup'
var privateEndpointPrivateDnsZoneGroupsStorageQueueName = '${privateEndpointStorageQueueName}/queuePrivateDnsZoneGroup'
var functionNetworkConfigName = '${functionAppName}/virtualNetwork'
var enableHa = (deploymentMode == 'production' ? true : false) 

resource eventHubNamespace_resource 'Microsoft.EventHub/namespaces@2024-01-01' = if (createNewEventHubNamespace) {
  name: eventHubNamespaceName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Standard'
    capacity: 1
  }
  properties: {
    minimumTlsVersion: '1.2'
    zoneRedundant: (enableHa ? true : null) 
    isAutoInflateEnabled: true
    maximumThroughputUnits: 20
  }
}

resource eventHubNamespaceName_eventHub 'Microsoft.EventHub/namespaces/eventhubs@2024-01-01' = if (createNewEventHub) {
  parent: eventHubNamespace_resource
  name: eventHub_name
  properties: {
    messageRetentionInDays: 1
  }
}

resource eventHubNamespaceName_eventHubName_eventHubConsumerGroup 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2024-01-01' = {
  parent: eventHubNamespaceName_eventHub
  name: eventHubConsumerGroupName
  properties: {}
}

resource eventHubNamespaceName_logConsumerAuthorizationRule 'Microsoft.EventHub/namespaces/AuthorizationRules@2024-01-01' = {
  parent: eventHubNamespace_resource
  name: logConsumerAuthorizationRuleName
  properties: {
    rights: [
      'Listen'
      'Send'
      // 'Manage'
    ]
  }
}

resource eventHubNamespaceName_logProducerAuthorizationRule 'Microsoft.EventHub/namespaces/AuthorizationRules@2024-01-01' = if (createActivityLogsDiagnosticSetting) {
  parent: eventHubNamespace_resource
  name: logProducerAuthorizationRuleName
  properties: {
    rights: [
      'Send'
    ]
  }
  dependsOn: [
    eventHubNamespaceName_logConsumerAuthorizationRule
  ]
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2022-09-01' = if (disablePublicAccessToStorageAccount) {
  name: virtualNetworkName
  location: location
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

resource privateEndpointStorageFile 'Microsoft.Network/privateEndpoints@2022-05-01' = if (disablePublicAccessToStorageAccount) {
  name: privateEndpointStorageFileName
  location: location
  properties: {
    subnet: {
      id: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetworkName, privateEndpointsSubnetName)
    }
    privateLinkServiceConnections: [
      {
        name: 'MyStorageFilePrivateLinkConnection'
        properties: {
          privateLinkServiceId: storageAccount.id
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

resource privateEndpointStorageBlob 'Microsoft.Network/privateEndpoints@2022-05-01' = if (disablePublicAccessToStorageAccount) {
  name: privateEndpointStorageBlobName
  location: location
  properties: {
    subnet: {
      id: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetworkName, privateEndpointsSubnetName)
    }
    privateLinkServiceConnections: [
      {
        name: 'MyStorageBlobPrivateLinkConnection'
        properties: {
          privateLinkServiceId: storageAccount.id
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

resource privateEndpointStorageTable 'Microsoft.Network/privateEndpoints@2022-05-01' = if (disablePublicAccessToStorageAccount) {
  name: privateEndpointStorageTableName
  location: location
  properties: {
    subnet: {
      id: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetworkName, privateEndpointsSubnetName)
    }
    privateLinkServiceConnections: [
      {
        name: 'MyStorageTablePrivateLinkConnection'
        properties: {
          privateLinkServiceId: storageAccount.id
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

resource privateEndpointStorageQueue 'Microsoft.Network/privateEndpoints@2022-05-01' = if (disablePublicAccessToStorageAccount) {
  name: privateEndpointStorageQueueName
  location: location
  properties: {
    subnet: {
      id: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetworkName, privateEndpointsSubnetName)
    }
    privateLinkServiceConnections: [
      {
        name: 'MyStorageQueuePrivateLinkConnection'
        properties: {
          privateLinkServiceId: storageAccount.id
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

resource privateEndpointPrivateDnsZoneGroupsStorageFile 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-05-01' = if (disablePublicAccessToStorageAccount) {
  name: privateEndpointPrivateDnsZoneGroupsStorageFileName
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
    privateEndpointStorageFile
  ]
}

resource privateEndpointPrivateDnsZoneGroupsStorageBlob 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-05-01' = if (disablePublicAccessToStorageAccount) {
  name: privateEndpointPrivateDnsZoneGroupsStorageBlobName
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
    privateEndpointStorageBlob
  ]
}

resource privateEndpointPrivateDnsZoneGroupsStorageTable 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-05-01' = if (disablePublicAccessToStorageAccount) {
  name: privateEndpointPrivateDnsZoneGroupsStorageTableName
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
    privateEndpointStorageTable
  ]
}

resource privateEndpointPrivateDnsZoneGroupsStorageQueue 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-05-01' = if (disablePublicAccessToStorageAccount) {
  name: privateEndpointPrivateDnsZoneGroupsStorageQueueName
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
    privateEndpointStorageQueue
  ]
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2024-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    networkAcls: (disablePublicAccessToStorageAccount ? json('{"bypass": "None", "defaultAction": "Deny"}') : null)
  }
}

// Defining the ASP Properties for Prod vs DevTest
var prdASP = {
  kind: 'elastic'
  properties: {
    perSiteScaling: true
    elasticScaleEnabled: true
    maximumElasticWorkerCount: 20
    zoneRedundant: true
  }
  sku: {
    name: 'EP1'
    tier: 'ElasticPremium'
    size: 'EP1'
    family: 'EP'
    capacity: 1
  }
}

var devASP = {
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

var aspConfig = (enableHa ? prdASP : devASP)

resource servicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  kind: (disablePublicAccessToStorageAccount ? aspConfig.kind : 'functionapp')
  location: location
  name: servicePlanName
  sku: (disablePublicAccessToStorageAccount ? aspConfig.sku : json('{ "name": "Y1", "tier": "Dynamic" }'))
  properties: (disablePublicAccessToStorageAccount ? aspConfig.properties: json('{ "name": "${servicePlanName}", "targetWorkerCount": 1, "targetWorkerSizeId": 1, "workerSize": "1", "numberOfWorkers": 1, "computeMode": "Dynamic" }'))
}


resource functionApp 'Microsoft.Web/sites@2020-12-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  properties: {
    serverFarmId: servicePlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'EVENTHUB_NAME'
          value: eventHub_name
        }
        {
          name: 'EVENTHUB_CONSUMER_CONNECTION'
          value: eventHubNamespaceName_logConsumerAuthorizationRule.listKeys().primaryConnectionString
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
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};AccountKey=${storageAccount.listkeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: (disablePublicAccessToStorageAccount ? eventHubForwarderFunctionArtifact : '0')
        }
      ]
      alwaysOn: (disablePublicAccessToStorageAccount && !(enableHa)? true : false )
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
    virtualNetwork
  ]
}

module activityLogsDiagnosticSettingsAtSubscriptionLevelDeployment 'modules/diagnosticSettings.bicep' = if (createActivityLogsDiagnosticSetting) {
  name: 'activityLogsDiagnosticSettingsAtSubscriptionLevelDeployment'
  scope: subscription(subscription().subscriptionId)
  params: {
    resourceId_subscription_subscriptionId_resourceGroup_name_Microsoft_EventHub_namespaces_AuthorizationRules_variables_eventHubNamespaceName_variables_logProducerAuthorizationRuleName: resourceId(
      subscription().subscriptionId,
      resourceGroup().name,
      'Microsoft.EventHub/namespaces/AuthorizationRules',
      eventHubNamespaceName,
      logProducerAuthorizationRuleName
    )
    variables_activityLogsDiagnosticSettingName: activityLogsDiagnosticSettingName
    variables_eventHubName: eventHub_name
    forwardAdministrativeAzureActivityLogs: forwardAdministrativeAzureActivityLogs
    forwardSecurityAzureActivityLogs: forwardSecurityAzureActivityLogs
    forwardServiceHealthAzureActivityLogs: forwardServiceHealthAzureActivityLogs
    forwardAlertAzureActivityLogs: forwardAlertAzureActivityLogs
    forwardRecommendationAzureActivityLogs: forwardRecommendationAzureActivityLogs
    forwardPolicyAzureActivityLogs: forwardPolicyAzureActivityLogs
    forwardAutoscaleAzureActivityLogs: forwardAutoscaleAzureActivityLogs
    forwardResourceHealthAzureActivityLogs: forwardResourceHealthAzureActivityLogs
  }
  dependsOn: [
    functionApp
    eventHubNamespaceName_eventHub
    eventHubNamespaceName_logProducerAuthorizationRule
  ]
}
