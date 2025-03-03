
param disableHighAvailability bool = false
param servicePlanName string
param deploymentMode string
param disablePublicAccessToStorageAccount bool
param production bool 
param location string

// Defining the ASP Properties for Prod vs DevTest
var prdASP = {
  kind: 'elastic'
  properties: {
    perSiteScaling: true
    elasticScaleEnabled: true
    maximumElasticWorkerCount: 20
    zoneRedundant: (disableHighAvailability ? false :  true)
  }
  sku: {
    name: 'EP1'
    tier: 'ElasticPremium'
    size: 'EP1'
    family: 'EP'
    capacity: 3
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
    zoneRedundant: false // Only works for Premium App Service Plans
  } 
  sku: {
    name: 'B1'
    tier: 'Basic'
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
var devTestConfig = (deploymentMode == 'devtest' &&  disablePublicAccessToStorageAccount ? devASP : defaultASP)
var aspConfig = (production ? prdASP : devTestConfig)

resource servicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  kind: aspConfig.kind
  location: location
  name: servicePlanName
  sku: aspConfig.sku
  properties: aspConfig.properties
}

output resourceId string = servicePlan.id
