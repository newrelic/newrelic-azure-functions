param location string = resourceGroup().location
param groupId string
param storageAccountResourceId string 
param virtualNetworkName string
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
