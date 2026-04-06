param location string = resourceGroup().location
param appName string = 'funapp-${uniqueString(resourceGroup().id)}'

// 1. Saugykla (Storage)
resource storage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: 'storeage${uniqueString(resourceGroup().id)}'
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
}

// Failų tarnyba
resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2023-01-01' existing = {
  parent: storage
  name: 'default'
}
resource logsShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' = {
  parent: fileService
  name: 'logs' // Čia rašysime logus
}

// 2. App Service Plan (Windows)
resource appPlan 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: 'plan-${appName}'
  location: location
  // KEIČIAME ČIA: Vietoj 'F1' (Free) naudojame 'B1' (Basic)
  sku: { 
    name: 'B1' 
    tier: 'Basic' 
  }
}

// 3. Web App
resource webApp 'Microsoft.Web/sites@2022-03-01' = {
  name: appName
  location: location
  properties: {
    serverFarmId: appPlan.id
    siteConfig: {
      netFrameworkVersion: 'v4.0'
      use32BitWorkerProcess: true
      // Prijungiame saugyklą kaip diską (X:)
      azureStorageAccounts: {
        'logai': {
          type: 'AzureFiles'
          accountName: storage.name
          shareName: logsShare.name
          mountPath: '/mounts/logs' // Windows aplinkoje tai taps virtualiu keliu
          accessKey: storage.listKeys().keys[0].value
        }
      }
    }
  }
}

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

output webAppName string = webApp.name
output storageName string = storage.name
output functionAppName string = functionApp.name
