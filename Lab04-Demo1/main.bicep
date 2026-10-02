targetScope = 'subscription'

param location string = 'swedencentral'
param rgName string = 'RG-Tinklas-Demo'

resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: rgName
  location: location
  tags: {
    Environment: 'Demo'
    Infrastructure: 'IaC'
  }
}

module networking './network.bicep' = {
  name: 'networkingDeployment'
  scope: resourceGroup(rg.name)
  params: {
    location: location
  }
}
