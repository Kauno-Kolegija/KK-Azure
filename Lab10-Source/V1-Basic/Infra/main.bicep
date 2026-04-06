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

output webAppName string = webApp.name
output storageName string = storage.name
