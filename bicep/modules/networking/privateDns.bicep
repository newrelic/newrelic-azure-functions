@description('Required. Name of the DNS zone to be created (e.g., "blob", "file", "queue", or "table")')
param dnsZoneName string

@description('Required. Resource ID of the Virtual Network to link with the Private DNS Zone')
param virtualNetworkResourceId string

@description('Required. Name of the Storage Account associated with the Private DNS Zone')
param storageAccountName string

var dnsSuffix = environment().suffixes.storage
var vnetName = split(virtualNetworkResourceId, '/')[8]
var dnsZoneNameFull =  'privatelink.${dnsZoneName}.${dnsSuffix}'

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: dnsZoneName
  location: 'global'
}

resource privateDnsZoneVirtualNetworkLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: '${dnsZoneNameFull}/${vnetName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetworkResourceId
    }
  }
  dependsOn: [
    privateDnsZone
  ]
}

resource privateEndpointPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-05-01' =  {
  name: '${storageAccountName}-${dnsZoneName}-private-endpoint/blobPrivateDnsZoneGroup'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}
