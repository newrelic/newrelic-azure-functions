@description('Required. New Relic License Key')
param newRelicLicenseKey string

@description('Required. Name of the Azure Storage Account that you want to capture the log blobs from.')
@minLength(3)
@maxLength(24)
param targetStorageAccountName string

@description('Required. Name of the container that contains the logs you want to forward.')
@minLength(3)
@maxLength(63)
param targetContainerName string

@description('Optional. Region where all resources included in this template will be deployed. Leave this blank to use the same region as the one of the resource group.')
param location string = ''

@description('Optional. The Logs API endpoint used to send your logs to. By default, it is https://log-api.newrelic.com/log/v1 if your account is in the United States (US) region. Otherwise, if you\'re in the European Union (EU) region, you should use https://log-api.eu.newrelic.com/log/v1, or if you\'re in the Japan (JP) region, you should use https://log-api.jp.nr-data.net/log/v1')
param newRelicEndpoint string = 'https://log-api.newrelic.com/log/v1'

@description('Optional. Maximum number of attempts the forwarder function will perform in the event of a failure while sending your data.')
@minValue(1)
param maxRetriesToResendLogs int = 3

@description('Optional. Number of milliseconds to wait between consecutive retries to send the logs.')
@minValue(100)
param retryInterval int = 2000

@description('Optional. Disables public network access to the Storage Account (please note that even without enabling this option, access to the Storage Account is secured). As a consequence, communication with the Service Account will be performed through a private Virtual Network (VNet). Please note that due to this, the hosting pricing plan for the Function app server farm will need to be upgraded to \'Basic\', as it is the minimum one providing VNet integration for Function apps (you can later upgrade this plan if you require more scaling options). Also note that the following extra resources will be created: a virtual network, a subnet, DNS zone names, virtual network links, private endpoints and a Storage Account file share.')
param disablePublicAccessToStorageAccount bool = false

var blobForwarderFunctionArtifact = 'https://github.com/newrelic/newrelic-azure-functions/releases/latest/download/LogForwarder.zip'
var onePerResourceGroupUniqueSuffix = uniqueString(resourceGroup().id)
var onePerResourceGroupAndStorageAccountAndContainer = uniqueString(resourceGroup().id, targetStorageAccountName, targetContainerName)
var functionAppName = 'nrlogs-blobforwarder-${onePerResourceGroupAndStorageAccountAndContainer}'
var location_var = ((location == '') ? resourceGroup().location : location)
var internalStorageAccountName = 'nrlogs${onePerResourceGroupAndStorageAccountAndContainer}'
var servicePlanName = 'nrlogs-serviceplan-${onePerResourceGroupUniqueSuffix}'
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
var privateEndpointStorageFileName = '${internalStorageAccountName}-file-private-endpoint'
var privateEndpointStorageTableName = '${internalStorageAccountName}-table-private-endpoint'
var privateEndpointStorageBlobName = '${internalStorageAccountName}-blob-private-endpoint'
var privateEndpointStorageQueueName = '${internalStorageAccountName}-queue-private-endpoint'
var privateEndpointPrivateDnsZoneGroupsStorageFileName = '${privateEndpointStorageFileName}/filePrivateDnsZoneGroup'
var privateEndpointPrivateDnsZoneGroupsStorageBlobName = '${privateEndpointStorageBlobName}/blobPrivateDnsZoneGroup'
var privateEndpointPrivateDnsZoneGroupsStorageTableName = '${privateEndpointStorageTableName}/tablePrivateDnsZoneGroup'
var privateEndpointPrivateDnsZoneGroupsStorageQueueName = '${privateEndpointStorageQueueName}/queuePrivateDnsZoneGroup'

// Customer's target Storage Account (the one holding the log blobs). Referenced
// as existing so we can read its access key for the TargetAccountConnection. The
// old apiVersion is intentional: its listKeys() returns the flat `key1` shape.
resource targetStorageAccount 'Microsoft.Storage/storageAccounts@2015-05-01-preview' existing = {
  name: targetStorageAccountName
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
          privateLinkServiceId: internalStorageAccount.id
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
          privateLinkServiceId: internalStorageAccount.id
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
          privateLinkServiceId: internalStorageAccount.id
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
          privateLinkServiceId: internalStorageAccount.id
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

resource internalStorageAccount 'Microsoft.Storage/storageAccounts@2024-01-01' = {
  name: internalStorageAccountName
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
      ? {
          bypass: 'None'
          defaultAction: 'Deny'
        }
      : null)
  }
}

resource servicePlan 'Microsoft.Web/serverfarms@2024-11-01' = {
  name: servicePlanName
  kind: (disablePublicAccessToStorageAccount ? 'app' : 'functionapp')
  location: location_var
  sku: (disablePublicAccessToStorageAccount
    ? {
        name: 'B1'
        tier: 'Basic'
        capacity: 1
      }
    : {
        name: 'Y1'
        tier: 'Dynamic'
      })
  properties: (disablePublicAccessToStorageAccount
    ? {
        maximumElasticWorkerCount: 1
      }
    : {
        name: servicePlanName
        targetWorkerCount: 1
        targetWorkerSizeId: 1
        workerSize: '1'
        numberOfWorkers: 1
        computeMode: 'Dynamic'
      })
}

resource functionApp 'Microsoft.Web/sites@2024-11-01' = {
  name: functionAppName
  location: location_var
  kind: 'functionapp'
  properties: {
    serverFarmId: servicePlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'TargetAccountConnection'
          value: 'DefaultEndpointsProtocol=https;AccountName=${targetStorageAccountName};AccountKey=${targetStorageAccount.listKeys().key1}'
        }
        {
          name: 'CONTAINER_NAME'
          value: targetContainerName
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
          name: 'NR_MAX_RETRIES'
          value: maxRetriesToResendLogs
        }
        {
          name: 'NR_RETRY_INTERVAL'
          value: retryInterval
        }
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${internalStorageAccountName};AccountKey=${internalStorageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
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
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'BLOB_FORWARDER_ENABLED'
          value: 'true'
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: (disablePublicAccessToStorageAccount ? blobForwarderFunctionArtifact : '0')
        }
      ]
      alwaysOn: disablePublicAccessToStorageAccount
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
    }
    httpsOnly: true
    publicNetworkAccess: (disablePublicAccessToStorageAccount ? 'Disabled' : 'Enabled')
  }
  dependsOn: [
    privateEndpointPrivateDnsZoneGroupsStorageBlob
    privateEndpointPrivateDnsZoneGroupsStorageFile
    privateEndpointPrivateDnsZoneGroupsStorageQueue
    privateEndpointPrivateDnsZoneGroupsStorageTable
    privateStorageBlobDnsZoneVirtualNetworkLink
    privateStorageFileDnsZoneVirtualNetworkLink
    privateStorageQueueDnsZoneVirtualNetworkLink
    privateStorageTableDnsZoneVirtualNetworkLink
  ]
}

resource functionAppName_ZipDeploy 'Microsoft.Web/sites/extensions@2022-03-01' = if (!disablePublicAccessToStorageAccount) {
  parent: functionApp
  // Azure accepts the ZipDeploy extension name; the Bicep type list for this
  // API version only enumerates MSDeploy/onedeploy, so suppress the false positive.
  #disable-next-line BCP088
  name: 'ZipDeploy'
  properties: {
    packageUri: blobForwarderFunctionArtifact
  }
}

resource functionAppName_networkConfig 'Microsoft.Web/sites/networkConfig@2022-03-01' = if (disablePublicAccessToStorageAccount) {
  parent: functionApp
  name: 'virtualNetwork'
  properties: {
    subnetResourceId: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetworkName, functionSubnetName)
    swiftSupported: true
  }
  dependsOn: [
    virtualNetwork
  ]
}
