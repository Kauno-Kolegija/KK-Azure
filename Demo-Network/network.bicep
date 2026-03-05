param location string
param adminUsername string = 'LabAdmin'
@secure()
param adminPassword string = 'Pake1sk173-1-$augu-s1ap7a#0d!'

// 1. Aplikacijų saugos grupės (ASG)
resource asgWeb 'Microsoft.Network/applicationSecurityGroups@2023-09-01' = {
  name: 'asg-web-servers'
  location: location
}

resource asgDB 'Microsoft.Network/applicationSecurityGroups@2023-09-01' = {
  name: 'asg-db-servers'
  location: location
}

resource asgFile 'Microsoft.Network/applicationSecurityGroups@2023-09-01' = {
  name: 'asg-file-servers'
  location: location
}

// 2. Tinklo saugos grupė (NSG)
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'nsg-projekto-saugumas'
  location: location
  properties: {
    securityRules: [
      // Leidžiame internetui pasiekti WEB serverius
      {
        name: 'AllowInternetToWeb'
        properties: {
          priority: 500
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80' // HTTP prievadas
          sourceAddressPrefix: 'Internet'
          destinationApplicationSecurityGroups: [ { id: asgWeb.id } ]
        }
      }
      // Leidžiame WEB serveriams pasiekti DB serverius
      {
        name: 'AllowWebToDB'
        properties: {
          priority: 550
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '1433' // SQL prievadas
          sourceApplicationSecurityGroups: [ { id: asgWeb.id } ]
          destinationApplicationSecurityGroups: [ { id: asgDB.id } ]
        }
      }
    ]
  }
}

// 3. Virtualus tinklas (VNet) su potinkliais
resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: 'vnet-projekto-tinklas'
  location: location
  properties: {
    addressSpace: { addressPrefixes: ['10.0.0.0/16'] }
    subnets: [
      {
        name: 'Subnet-Web'
        properties: {
          addressPrefix: '10.0.1.0/24'
          networkSecurityGroup: { id: nsg.id }
        }
      }
      {
        name: 'Subnet-DB'
        properties: {
          addressPrefix: '10.0.2.0/24'
          networkSecurityGroup: { id: nsg.id }
        }
      }
 /*
      {
        name: 'Subnet-File'
        properties: {
          addressPrefix: '10.0.3.0/24'
          networkSecurityGroup: { id: nsg.id }
        }
      }
*/
    ]
  }
}

// Viešas IP adresas
resource publicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: 'pip-projekto-isore'
  location: location
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// 4. Load Balancer (LB)
resource loadBalancer 'Microsoft.Network/loadBalancers@2023-09-01' = {
  name: 'lb-projekto-srautas'
  location: location
  sku: { name: 'Standard' }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'PublicFrontendIP'
        properties: {
          publicIPAddress: { id: publicIp.id } // LB naudoja mūsų Public IP
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'WebBackendPool'
      }
    ]
    loadBalancingRules: [
      {
        name: 'HTTP-Rule'
        properties: {
          frontendIPConfiguration: { id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', 'lb-projekto-srautas', 'PublicFrontendIP') }
          backendAddressPool: { id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', 'lb-projekto-srautas', 'WebBackendPool') }
          protocol: 'Tcp'
          frontendPort: 80
          backendPort: 80
          enableFloatingIP: false
          idleTimeoutInMinutes: 4
        }
      }
    ]
  }
}

// 5. Sukuriame 4 Web NIC plokštes, bet TIK 2 priskiriame Load Balanceriui
resource nicWeb 'Microsoft.Network/networkInterfaces@2023-09-01' = [for i in range(1, 4): { 
  name: 'nic-web-0${i}'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: { id: vnet.properties.subnets[0].id }
          applicationSecurityGroups: [ { id: asgWeb.id } ]
          
          // ČIA YRA MAGIJA: Priskiriame Backend Pool'ui tik jei indeksas 'i' yra 1 arba 2.
          // Jei 'i' yra 3 arba 4, priskiriame tuščią masyvą [].
          loadBalancerBackendAddressPools: i <= 2 ? [
            {
              id: loadBalancer.properties.backendAddressPools[0].id
            }
          ] : []

        }
      }
    ]
  }
}]

// Sukuriame 2 DB NIC plokštes
resource nicDB 'Microsoft.Network/networkInterfaces@2023-09-01' = [for i in range(1, 2): { 
  name: 'nic-db-0${i}'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: { id: vnet.properties.subnets[1].id }
          applicationSecurityGroups: [ { id: asgDB.id } ]
        }
      }
    ]
  }
}]

// 6. Pridedame vieną Virtualią Mašiną (VM)
resource vmWeb01 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: 'vm-web-01'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B2s' // Pasirinktas dydis
    }
    osProfile: {
      computerName: 'vmweb01'
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-datacenter-azure-edition'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nicWeb[0].id // Susiejame su pirmuoju NIC (nic-web-01) iš masyvo
        }
      ]
    }
  }
}


// Grąžiname informaciją po sėkmingo sukūrimo
output vnetName string = vnet.name
output webSubnetId string = vnet.properties.subnets[0].id
output publicIpAddress string = publicIp.properties.ipAddress
output loadBalancerName string = loadBalancer.name
