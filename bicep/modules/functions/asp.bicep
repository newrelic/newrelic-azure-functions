
@description('Optional. Flag to disable high availability features. Default is false.')
param disableHighAvailability bool = false

@description('Required. Name of the App Service Plan to be created.')
param servicePlanName string

@description('Required. Deployment mode for the App Service Plan. Valid values are "production" or "devtest".')
param deploymentMode string

@description('Required. Flag to control public access to the associated Storage Account.')
param disablePublicAccessToStorageAccount bool

@description('Required. Azure region where the App Service Plan will be deployed.')
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
    capacity: 3 // High Availability requires more than 1 instance to run
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

// Determining which configuration to use - As the config is very different depending upon the mode used.
var isProduction = (deploymentMode == 'production' ? true : false ) 
var devTestConfig = (deploymentMode == 'devtest' && disablePublicAccessToStorageAccount ? devASP : defaultASP)
var aspConfig = (isProduction ? prdASP : devTestConfig)

resource servicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  kind: aspConfig.kind
  location: location
  name: servicePlanName
  sku: aspConfig.sku
  properties: aspConfig.properties
}

output resourceId string = servicePlan.id
