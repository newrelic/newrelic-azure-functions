@description('Required. New Relic License Key')
param newRelicLicenseKey string

@description('Optional. Event Hub Namespace where all logs to be forwarded to New Relic are being sent to. Leave this blank for a new namespace to be created automatically (its name will start with \'nrlogs-\').')
param eventHubNamespace string = ''

@description('Optional. Event Hub where all the Azure Platform logs are being sent to in order to be forwarded to New Relic. Leave this blank for a new Event Hub to be created automatically (its name will be \'nrlogs\').')
param eventHubName string = ''

@description('Optional. Region where all resources included in this template will be deployed. Leave this blank to use the same region as the one of the resource group.')
param location string = ''

@description('Optional. The Logs API endpoint used to send your logs to. By default, it is https://log-api.newrelic.com/log/v1 if your account is in the United States (US) region. Otherwise, if you\'re in the European Union (EU) region, you should use https://log-api.eu.newrelic.com/log/v1, or if you\'re in the Japan (JP) region, you should use https://log-api.jp.nr-data.net/log/v1')
param newRelicEndpoint string = 'https://log-api.newrelic.com/log/v1'

@description('Optional. List of semicolon-separated custom attributes that you would like to enrich the forwarded logs with. This can be useful, for example, if you want to indicate common attributes shared by all the logs collected in this account, such as: \'environment:production;department:sales;country:Germany\'')
param logCustomAttributes string = ''

@description('Optional. Maximum number of attempts the forwarder function will perform in the event of a failure while sending your data.')
@minValue(1)
param maxRetriesToResendLogs int = 3

@description('Optional. Number of milliseconds to wait between consecutive retries to send the logs.')
@minValue(100)
param retryInterval int = 2000

@description('Optional. Controls Event Hub sizing and Function App scale-out. If set to \'Enterprise\', the Event Hub namespace is auto-inflated (higher maximum throughput units and partition count) and the Function App is allowed more instances/workers; otherwise smaller defaults are used. This no longer selects the hosting plan - use the functionAppPlan parameter to choose the plan.')
@allowed([
  'Basic'
  'Enterprise'
])
param scalingMode string = 'Basic'

@description('Optional. Function App hosting plan. FlexConsumption (default) is the modern serverless plan, preferred where available. ElasticPremium is for production/bursty workloads or regions without Flex. Basic is a low-cost dedicated tier that still supports private networking. Consumption is pay-per-use for public dev/test only - deployment fails if combined with disablePublicAccessToStorageAccount=true. Note: Azure does not allow in-place plan changes across tier families; moving an existing deployment to a different plan requires a fresh deployment in a new resource group.')
@allowed([
  'FlexConsumption'
  'ElasticPremium'
  'Basic'
  'Consumption'
])
param functionAppPlan string = 'FlexConsumption'

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
param disablePublicAccessToStorageAccount bool = false

@description('Optional. Maximum number of events that will be delivered in a batch to the function. Default is 500.')
@minValue(1)
param maxEventBatchSize int = 500

@description('Optional. Minimum number of events that will be delivered in a batch to the function. Default is 20.')
@minValue(1)
param minEventBatchSize int = 20

@description('Optional. Maximum amount of time to wait to build up a batch before delivering to the function (in format HH:MM:SS). Default is 00:00:30.')
param maxWaitTime string = '00:00:30'

@description('Optional. Authentication method for connecting to the Event Hub. Use Local Authentication to connect via a shared access key connection string, or Managed Identity for keyless authentication using a system-assigned Azure AD identity.')
@allowed([
  'Local Authentication'
  'Managed Identity'
])
param authenticationMode string = 'Local Authentication'

var location_var = ((location == '') ? resourceGroup().location : location)
var onePerResourceGroupUniqueSuffix = uniqueString(resourceGroup().id)
var createNewEventHubNamespace = (eventHubNamespace == '')
var eventHubNamespaceName = (createNewEventHubNamespace
  ? 'nrlogs-eventhub-namespace-${onePerResourceGroupUniqueSuffix}'
  : eventHubNamespace)
var createNewEventHub = (eventHubName == '')
var eventHubName_var = (createNewEventHub ? 'nrlogs-eventhub' : eventHubName)
var eventHubConsumerGroupName = 'nrlogs-consumergroup'
var logConsumerAuthorizationRuleName = 'nrlogs-consumer-policy'
var logProducerAuthorizationRuleName = 'nrlogs-producer-policy'
var storageAccountName = 'nrlogs${onePerResourceGroupUniqueSuffix}'
var servicePlanName = 'nrlogs-serviceplan-${onePerResourceGroupUniqueSuffix}'
var onePerResourceGroupAndEventHubUniqueSuffix = uniqueString(
  resourceGroup().id,
  eventHubNamespaceName,
  eventHubName_var
)
var functionAppName = 'nrlogs-eventhubforwarder-${onePerResourceGroupAndEventHubUniqueSuffix}'
var activityLogsDiagnosticSettingName = 'nrlogs-activity-log-diagnostic-setting-${onePerResourceGroupAndEventHubUniqueSuffix}'
var createActivityLogsDiagnosticSetting = (forwardAdministrativeAzureActivityLogs || forwardAlertAzureActivityLogs || forwardAutoscaleAzureActivityLogs || forwardPolicyAzureActivityLogs || forwardRecommendationAzureActivityLogs || forwardResourceHealthAzureActivityLogs || forwardSecurityAzureActivityLogs || forwardServiceHealthAzureActivityLogs)
var eventHubForwarderFunctionArtifact = 'https://github.com/newrelic/newrelic-azure-functions/releases/latest/download/LogForwarder.zip'
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
var planConfig = {
  FlexConsumption: {
    kind: 'functionapp,linux'
    properties: {
      reserved: true
    }
    sku: {
      tier: 'FlexConsumption'
      name: 'FC1'
    }
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: 'https://${storageAccountName}.blob.${environment().suffixes.storage}/deployments'
          authentication: {
            type: 'SystemAssignedIdentity'
          }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: ((scalingMode == 'Enterprise') ? 32 : 4)
        instanceMemoryMB: 2048
      }
      runtime: {
        name: 'node'
        version: '22'
      }
    }
    subnetDelegation: 'Microsoft.App/environments'
    usesRunFromPackage: false
    usesIdentityStorage: true
    functionAppReserved: true
  }
  ElasticPremium: {
    kind: 'elastic'
    properties: {
      perSiteScaling: true
      elasticScaleEnabled: true
      maximumElasticWorkerCount: (scalingMode == 'Enterprise' ? 20 : 4)
      zoneRedundant: false
    }
    sku: {
      name: 'EP1'
      tier: 'ElasticPremium'
      size: 'EP1'
      family: 'EP'
      capacity: 1
    }
    functionAppConfig: null
    subnetDelegation: 'Microsoft.Web/serverFarms'
    usesRunFromPackage: true
    usesIdentityStorage: false
    functionAppReserved: false
  }
  Basic: {
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
    functionAppConfig: null
    subnetDelegation: 'Microsoft.Web/serverFarms'
    usesRunFromPackage: true
    usesIdentityStorage: false
    functionAppReserved: false
  }
  Consumption: {
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
    functionAppConfig: null
    subnetDelegation: ''
    usesRunFromPackage: true
    usesIdentityStorage: false
    functionAppReserved: false
  }
}
var pc = planConfig[functionAppPlan]
var runFromPackageSetting = ((pc.usesRunFromPackage && disablePublicAccessToStorageAccount)
  ? [
      {
        name: 'WEBSITE_RUN_FROM_PACKAGE'
        value: eventHubForwarderFunctionArtifact
      }
    ]
  : [])

var useManagedIdentity = authenticationMode == 'Managed Identity'
var eventHubsDataReceiverRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a638d3c7-ab3a-418d-83e6-5f17a39d4fde')
var storageBlobDataOwnerRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
var storageQueueDataContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '974c5e8b-45b9-4653-ba55-5f855dd0fb88')
var storageTableDataContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')
var websiteContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'de139f84-1756-47ae-9be6-808fbbe84772')
var storageFileDataPrivilegedContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '69566ab7-960f-475b-8e7c-b3118f30c6bd')
var deploymentIdentityName = 'nrlogs-deploy-identity-${onePerResourceGroupAndEventHubUniqueSuffix}'
var deploymentScriptName = 'nrlogs-deploy-script-${onePerResourceGroupAndEventHubUniqueSuffix}'
var deploymentScriptsSubnetName = 'deployment-scripts-subnet'
var deploymentScriptsSubnetId = resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetworkName, deploymentScriptsSubnetName)
var sitesPrivateDnsZoneName = 'privatelink.azurewebsites.net'
var sitesPrivateDnsZoneVirtualNetworkLinkName = '${sitesPrivateDnsZoneName}/${virtualNetworkName}-link'
var functionAppPrivateEndpointName = '${functionAppName}-sites-private-endpoint'
var functionAppPrivateEndpointDnsZoneGroupName = '${functionAppPrivateEndpointName}/sitesPrivateDnsZoneGroup'
var managedIdentityAppSettings = [
  {
    name: 'EVENTHUB_CONSUMER_CONNECTION__fullyQualifiedNamespace'
    value: '${eventHubNamespaceName}.servicebus.windows.net'
  }
]

resource eventHubNamespace_resource 'Microsoft.EventHub/namespaces@2024-01-01' = if (createNewEventHubNamespace) {
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
  }
}

resource eventHubNamespaceName_eventHub 'Microsoft.EventHub/namespaces/eventhubs@2024-01-01' = if (createNewEventHub) {
  parent: eventHubNamespace_resource
  name: '${eventHubName_var}'
  location: location_var
  properties: {
    messageRetentionInDays: 1
    partitionCount: ((scalingMode == 'Enterprise') ? 32 : 4)
  }
}

resource eventHubNamespaceName_eventHubName_eventHubConsumerGroup 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2017-04-01' = {
  parent: eventHubNamespaceName_eventHub
  name: eventHubConsumerGroupName
  properties: {}
}

resource eventHubNamespaceName_logConsumerAuthorizationRule 'Microsoft.EventHub/namespaces/AuthorizationRules@2024-01-01' = {
  parent: eventHubNamespace_resource
  name: '${logConsumerAuthorizationRuleName}'
  location: location_var
  properties: {
    rights: [
      'Listen'
    ]
  }
}

resource eventHubNamespaceRef 'Microsoft.EventHub/namespaces@2024-01-01' existing = {
  name: eventHubNamespaceName
}

resource eventHubNamespaceName_logProducerAuthorizationRule 'Microsoft.EventHub/namespaces/AuthorizationRules@2024-01-01' = if (createActivityLogsDiagnosticSetting) {
  parent: eventHubNamespace_resource
  name: '${logProducerAuthorizationRuleName}'
  location: location_var
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
          delegations: (empty(pc.subnetDelegation)
            ? []
            : [
                {
                  name: 'delegation'
                  properties: {
                    serviceName: pc.subnetDelegation
                  }
                }
              ])
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
      {
        name: deploymentScriptsSubnetName
        properties: {
          addressPrefix: '10.2.2.0/28'
          delegations: [
            {
              name: 'delegation'
              properties: {
                serviceName: 'Microsoft.ContainerInstance/containerGroups'
              }
            }
          ]
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
  location: location_var
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
  location: location_var
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
  location: location_var
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
  location: location_var
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
  location: location_var
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: (disablePublicAccessToStorageAccount ? 'Disabled' : 'Enabled')
    allowBlobPublicAccess: false
    networkAcls: (disablePublicAccessToStorageAccount
      ? json('{"bypass": "AzureServices", "defaultAction": "Deny"}')
      : json('null'))
  }
}

resource storageAccountName_blobServices 'Microsoft.Storage/storageAccounts/blobServices@2024-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {}
}

resource storageAccountName_deploymentsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2024-01-01' = {
  parent: storageAccountName_blobServices
  name: 'deployments'
  properties: {
    publicAccess: 'None'
  }
}

resource invalidConsumptionPrivateCombo 'Microsoft.Resources/deploymentScripts@2023-08-01' = if ((functionAppPlan == 'Consumption') && disablePublicAccessToStorageAccount) {
  name: 'nrlogs-validate-plan-${onePerResourceGroupAndEventHubUniqueSuffix}'
  location: location_var
  kind: 'AzureCLI'
  properties: {
    azCliVersion: '2.61.0'
    timeout: 'PT5M'
    retentionInterval: 'PT1H'
    cleanupPreference: 'OnSuccess'
    scriptContent: 'echo \'ERROR: Consumption (Y1) plan does not support private networking. Choose ElasticPremium or Basic for a private deployment, or set disablePublicAccessToStorageAccount=false to keep Consumption on the public network.\' >&2; exit 1'
  }
}

resource servicePlan 'Microsoft.Web/serverfarms@2024-11-01' = {
  name: servicePlanName
  kind: pc.kind
  location: location_var
  sku: pc.sku
  properties: pc.properties
}

resource functionApp 'Microsoft.Web/sites@2024-11-01' = {
  name: functionAppName
  location: location_var
  kind: (pc.functionAppReserved ? 'functionapp,linux' : 'functionapp')
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: servicePlan.id
    reserved: pc.functionAppReserved
    httpsOnly: true
    virtualNetworkSubnetId: ((disablePublicAccessToStorageAccount && !empty(pc.subnetDelegation)) ? resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetworkName, functionSubnetName) : null)
    functionAppConfig: pc.functionAppConfig
    siteConfig: union({
      appSettings: concat(
        [
          {
            name: 'EVENTHUB_NAME'
            value: eventHubName_var
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
            value: maxRetriesToResendLogs
          }
          {
            name: 'NR_RETRY_INTERVAL'
            value: retryInterval
          }
          {
            name: 'FUNCTIONS_EXTENSION_VERSION'
            value: '~4'
          }
          {
            name: 'EVENTHUB_FORWARDER_ENABLED'
            value: 'true'
          }
          {
            name: 'AzureFunctionsJobHost__extensions__eventHubs__maxEventBatchSize'
            value: string(maxEventBatchSize)
          }
          {
            name: 'AzureFunctionsJobHost__extensions__eventHubs__minEventBatchSize'
            value: string(minEventBatchSize)
          }
          {
            name: 'AzureFunctionsJobHost__extensions__eventHubs__maxWaitTime'
            value: maxWaitTime
          }
        ],
        ((functionAppPlan == 'FlexConsumption')
          ? []
          : [
              {
                name: 'FUNCTIONS_WORKER_RUNTIME'
                value: 'node'
              }
              {
                name: 'WEBSITE_NODE_DEFAULT_VERSION'
                value: '~22'
              }
            ]),
        ((pc.usesIdentityStorage || useManagedIdentity)
          ? [
              {
                name: 'AzureWebJobsStorage__accountName'
                value: storageAccountName
              }
            ]
          : [
              {
                name: 'AzureWebJobsStorage'
                value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
              }
            ]),
        (useManagedIdentity
          ? managedIdentityAppSettings
          : [
              {
                name: 'EVENTHUB_CONSUMER_CONNECTION'
                value: listKeys(eventHubNamespaceName_logConsumerAuthorizationRule.id, '2024-01-01').primaryConnectionString
              }
            ]),
        runFromPackageSetting
      )
      vnetRouteAllEnabled: ((functionAppPlan == 'FlexConsumption') && disablePublicAccessToStorageAccount)
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      publicNetworkAccess: (disablePublicAccessToStorageAccount ? 'Disabled' : 'Enabled')
    }, ((functionAppPlan == 'Basic')
      ? {
          alwaysOn: true
        }
      : {}))
  }
  dependsOn: [
    invalidConsumptionPrivateCombo
    storageAccountName_deploymentsContainer
    privateEndpointPrivateDnsZoneGroupsStorageTable
    privateEndpointPrivateDnsZoneGroupsStorageFile
  ]
}

resource eventHubDataReceiverRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (useManagedIdentity) {
  name: guid(eventHubNamespaceRef.id, functionApp.id, eventHubsDataReceiverRoleDefinitionId)
  scope: eventHubNamespaceRef
  properties: {
    roleDefinitionId: eventHubsDataReceiverRoleDefinitionId
    principalId: useManagedIdentity ? functionApp.identity.principalId : ''
    principalType: 'ServicePrincipal'
  }
}

resource functionAppStorageBlobDataOwnerAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(functionApp.id, storageAccount.id, 'StorageBlobDataOwner')
  properties: {
    roleDefinitionId: storageBlobDataOwnerRoleId
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource functionAppStorageQueueDataContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(functionApp.id, storageAccount.id, 'StorageQueueDataContributor')
  properties: {
    roleDefinitionId: storageQueueDataContributorRoleId
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource functionAppStorageTableDataContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(functionApp.id, storageAccount.id, 'StorageTableDataContributor')
  properties: {
    roleDefinitionId: storageTableDataContributorRoleId
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource deploymentIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: deploymentIdentityName
  location: location_var
}

resource deploymentScriptWebsiteContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (functionAppPlan == 'FlexConsumption') {
  scope: functionApp
  name: guid(functionApp.id, deploymentIdentityName, 'WebsiteContributor')
  properties: {
    roleDefinitionId: websiteContributorRoleId
    principalId: deploymentIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource deploymentScriptStorageFileContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if ((functionAppPlan == 'FlexConsumption') && disablePublicAccessToStorageAccount) {
  scope: storageAccount
  name: guid(storageAccount.id, deploymentIdentityName, 'StorageFileDataPrivilegedContributor')
  properties: {
    roleDefinitionId: storageFileDataPrivilegedContributorRoleId
    principalId: deploymentIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource functionAppSitesPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if ((functionAppPlan == 'FlexConsumption') && disablePublicAccessToStorageAccount) {
  name: sitesPrivateDnsZoneName
  location: 'global'
}

resource functionAppSitesPrivateDnsZoneVirtualNetworkLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if ((functionAppPlan == 'FlexConsumption') && disablePublicAccessToStorageAccount) {
  name: sitesPrivateDnsZoneVirtualNetworkLinkName
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: resourceId('Microsoft.Network/virtualNetworks', virtualNetworkName)
    }
  }
  dependsOn: [
    functionAppSitesPrivateDnsZone
    virtualNetwork
  ]
}

resource functionAppSitesPrivateEndpoint 'Microsoft.Network/privateEndpoints@2022-05-01' = if ((functionAppPlan == 'FlexConsumption') && disablePublicAccessToStorageAccount) {
  name: functionAppPrivateEndpointName
  location: location_var
  properties: {
    subnet: {
      id: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetworkName, privateEndpointsSubnetName)
    }
    privateLinkServiceConnections: [
      {
        name: 'MyFunctionAppSitesPrivateLinkConnection'
        properties: {
          privateLinkServiceId: functionApp.id
          groupIds: [
            'sites'
          ]
        }
      }
    ]
  }
  dependsOn: [
    virtualNetwork
  ]
}

resource functionAppSitesPrivateEndpointDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-05-01' = if ((functionAppPlan == 'FlexConsumption') && disablePublicAccessToStorageAccount) {
  name: functionAppPrivateEndpointDnsZoneGroupName
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config'
        properties: {
          privateDnsZoneId: resourceId('Microsoft.Network/privateDnsZones', sitesPrivateDnsZoneName)
        }
      }
    ]
  }
  dependsOn: [
    functionAppSitesPrivateEndpoint
    functionAppSitesPrivateDnsZone
  ]
}

resource deploymentScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = if (functionAppPlan == 'FlexConsumption') {
  name: deploymentScriptName
  location: location_var
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${deploymentIdentity.id}': {}
    }
  }
  properties: {
    azCliVersion: '2.61.0'
    timeout: 'PT15M'
    retentionInterval: 'PT1H'
    cleanupPreference: 'OnSuccess'
    containerSettings: (disablePublicAccessToStorageAccount
      ? {
          subnetIds: [
            {
              id: deploymentScriptsSubnetId
            }
          ]
        }
      : null)
    storageAccountSettings: (disablePublicAccessToStorageAccount
      ? {
          storageAccountName: storageAccountName
        }
      : null)
    environmentVariables: [
      {
        name: 'ZIP_URL'
        value: eventHubForwarderFunctionArtifact
      }
      {
        name: 'FUNCTION_APP'
        value: functionAppName
      }
      {
        name: 'RESOURCE_GROUP'
        value: resourceGroup().name
      }
    ]
    scriptContent: 'set -euo pipefail\necho \'Downloading package...\'\npython3 -c "import os, urllib.request; urllib.request.urlretrieve(os.environ[\'ZIP_URL\'], \'/tmp/package.zip\')"\nls -la /tmp/package.zip\necho \'Deploying via az functionapp deployment source config-zip...\'\naz functionapp deployment source config-zip --resource-group "$RESOURCE_GROUP" --name "$FUNCTION_APP" --src /tmp/package.zip --build-remote false --timeout 300\n'
  }
  dependsOn: [
    functionApp
    deploymentScriptWebsiteContributorAssignment
    deploymentScriptStorageFileContributorAssignment
    functionAppSitesPrivateEndpointDnsZoneGroup
    privateEndpointPrivateDnsZoneGroupsStorageBlob
    privateEndpointPrivateDnsZoneGroupsStorageFile
  ]
}

resource functionAppName_ZipDeploy 'Microsoft.Web/sites/extensions@2022-03-01' = if (!disablePublicAccessToStorageAccount && pc.usesRunFromPackage) {
  parent: functionApp
  // Azure accepts the ZipDeploy extension name; the Bicep type list for this
  // API version only enumerates MSDeploy/onedeploy, so suppress the false positive.
  #disable-next-line BCP088
  name: 'ZipDeploy'
  properties: {
    packageUri: eventHubForwarderFunctionArtifact
  }
}

module activityLogsDiagnosticSettingsAtSubscriptionLevelDeployment './activityLogConfiguration.bicep' = if (createActivityLogsDiagnosticSetting) {
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
    variables_eventHubName: eventHubName_var
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

output connectionString string = useManagedIdentity ? '' : listKeys(eventHubNamespaceName_logConsumerAuthorizationRule.id, '2024-01-01').primaryConnectionString
output eventHubName string = eventHubName_var
