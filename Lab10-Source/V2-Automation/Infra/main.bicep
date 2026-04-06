// --- NAUJA DALIS (v2): ARCHYVAVIMO INFRASTRUKTŪRA ---

// 1. Blob tarnyba ir konteineris
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' existing = {
  parent: storage
  name: 'default'
}

resource archiveContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: 'archyvas'
  properties: {
    publicAccess: 'None'
  }
}

// 2. Function App
resource functionApp 'Microsoft.Web/sites@2021-01-15' = {
  name: 'func-${appName}'
  location: location
  kind: 'functionapp'
  properties: {
    serverFarmId: appPlan.id 
    siteConfig: {
      // SVARBU: Keičiame '7.2' į '7.4'
      powerShellVersion: '7.4'
      alwaysOn: true
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storage.name};AccountKey=${storage.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'powershell'
        }
        {
          // Užtikriname, kad naudojama 4-oji funkcijų versija
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'TargetStorageConnection'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storage.name};AccountKey=${storage.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
        }
      ]
    }
  }
}
