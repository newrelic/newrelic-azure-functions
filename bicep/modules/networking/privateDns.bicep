
param dnsZoneName string
param virtualNetworkResourceId string
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
