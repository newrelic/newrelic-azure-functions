@description('Required. Azure region where the Private Endpoint will be deployed. Defaults to resource group location.')
param location string

@description('Required. Group ID for the Private Endpoint service (e.g., "blob", "file", "queue", "table")')
param groupId string

@description('Required. Resource ID of the Storage Account to connect to')
param storageAccountResourceId string 

@description('Required. Name of the Virtual Network where the Private Endpoint will be created')
param virtualNetworkName string

@description('Required. Name of the subnet where the Private Endpoint will be deployed')
param privateEndpointsSubnetName string

var storageAccountName = split(storageAccountResourceId, '/')[8]

resource privateEndpointStorageFile 'Microsoft.Network/privateEndpoints@2022-05-01' = {
  name: '${storageAccountName}-${groupId}-private-endpoint'
  location: location
  properties: {
    subnet: {
      id: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetworkName, privateEndpointsSubnetName)
    }
    privateLinkServiceConnections: [
      {
        name: 'MyStorageFilePrivateLinkConnection'
        properties: {
          privateLinkServiceId: storageAccountResourceId
          groupIds: [
            groupId
          ]
        }
      }
    ]
  }
}
