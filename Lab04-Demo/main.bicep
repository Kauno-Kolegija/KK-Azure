@description('Azure region')
param location string = resourceGroup().location

@description('Linux administrator username')
param adminUsername string = 'azureuser'

@secure()
@description('Linux administrator password')
param adminPassword string

@description('VM size for demo virtual machines')
param vmSize string = 'Standard_B1s'

var vnetAName = 'vnet-demo-a'
var vnetBName = 'vnet-demo-b'

var subnetWebName = 'snet-web'
var subnetDbName = 'snet-db'
var subnetAppName = 'snet-app'

//
// Application Security Groups
//

resource asgWeb 'Microsoft.Network/applicationSecurityGroups@2024-05-01' = {
  name: 'asg-web-servers'
  location: location
}

resource asgDb 'Microsoft.Network/applicationSecurityGroups@2024-05-01' = {
  name: 'asg-db-servers'
  location: location
}

//
// Network Security Groups
//

resource nsgWeb 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-web'
  location: location

  properties: {
    securityRules: [
      {
        name: 'Allow-SSH'
        properties: {
          priority: 200
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-HTTP'
        properties: {
          priority: 210
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

resource nsgDb 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-db'
  location: location

  properties: {
    securityRules: [
      {
        name: 'Allow-Web-ASG-HTTP'
        properties: {
          priority: 200
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'

          sourceApplicationSecurityGroups: [
            {
              id: asgWeb.id
            }
          ]

          destinationApplicationSecurityGroups: [
            {
              id: asgDb.id
            }
          ]
        }
      }
    ]
  }
}

resource nsgApp 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-app'
  location: location

  properties: {
    securityRules: [
      {
        name: 'Allow-HTTP-VNet'
        properties: {
          priority: 200
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

//
// Virtual Networks
//

resource vnetA 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetAName
  location: location

  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.10.0.0/16'
      ]
    }

    subnets: [
      {
        name: subnetWebName
        properties: {
          addressPrefix: '10.10.1.0/24'

          networkSecurityGroup: {
            id: nsgWeb.id
          }
        }
      }
      {
        name: subnetDbName
        properties: {
          addressPrefix: '10.10.2.0/24'

          networkSecurityGroup: {
            id: nsgDb.id
          }
        }
      }
    ]
  }
}

resource vnetB 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetBName
  location: location

  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.20.0.0/16'
      ]
    }

    subnets: [
      {
        name: subnetAppName
        properties: {
          addressPrefix: '10.20.1.0/24'

          networkSecurityGroup: {
            id: nsgApp.id
          }
        }
      }
    ]
  }
}

//
// Public IP for Web-01
//

resource pipWeb01 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: 'pip-web-01'
  location: location

  sku: {
    name: 'Standard'
  }

  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

//
// Network Interfaces
//

resource nicWeb01 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: 'nic-web-01'
  location: location

  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'

        properties: {
          privateIPAllocationMethod: 'Dynamic'

          subnet: {
            id: resourceId(
              'Microsoft.Network/virtualNetworks/subnets',
              vnetA.name,
              subnetWebName
            )
          }

          publicIPAddress: {
            id: pipWeb01.id
          }

          applicationSecurityGroups: [
            {
              id: asgWeb.id
            }
          ]
        }
      }
    ]
  }
}

resource nicWeb02 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: 'nic-web-02'
  location: location

  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'

        properties: {
          privateIPAllocationMethod: 'Dynamic'

          subnet: {
            id: resourceId(
              'Microsoft.Network/virtualNetworks/subnets',
              vnetA.name,
              subnetWebName
            )
          }

          applicationSecurityGroups: [
            {
              id: asgWeb.id
            }
          ]
        }
      }
    ]
  }
}

resource nicDb01 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: 'nic-db-01'
  location: location

  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'

        properties: {
          privateIPAllocationMethod: 'Dynamic'

          subnet: {
            id: resourceId(
              'Microsoft.Network/virtualNetworks/subnets',
              vnetA.name,
              subnetDbName
            )
          }

          applicationSecurityGroups: [
            {
              id: asgDb.id
            }
          ]
        }
      }
    ]
  }
}

resource nicApp01 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: 'nic-app-01'
  location: location

  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'

        properties: {
          privateIPAllocationMethod: 'Dynamic'

          subnet: {
            id: resourceId(
              'Microsoft.Network/virtualNetworks/subnets',
              vnetB.name,
              subnetAppName
            )
          }
        }
      }
    ]
  }
}

//
// cloud-init
//

var web01CloudInit = '''
#cloud-config
package_update: true
packages:
  - nginx

runcmd:
  - echo '<h1>WEB-01</h1><p>VNet-A / Web Subnet</p>' > /var/www/html/index.html
  - systemctl enable nginx
  - systemctl restart nginx
'''

var web02CloudInit = '''
#cloud-config
package_update: true
packages:
  - nginx

runcmd:
  - echo '<h1>WEB-02</h1><p>VNet-A / Web Subnet</p>' > /var/www/html/index.html
  - systemctl enable nginx
  - systemctl restart nginx
'''

var db01CloudInit = '''
#cloud-config
package_update: true
packages:
  - nginx

runcmd:
  - echo '<h1>DB-01</h1><p>VNet-A / DB Subnet</p>' > /var/www/html/index.html
  - systemctl enable nginx
  - systemctl restart nginx
'''

var app01CloudInit = '''
#cloud-config
package_update: true
packages:
  - nginx

runcmd:
  - echo '<h1>APP-01</h1><p>VNet-B / App Subnet</p>' > /var/www/html/index.html
  - systemctl enable nginx
  - systemctl restart nginx
'''

//
// Virtual Machines
//

resource vmWeb01 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: 'vm-web-01'
  location: location

  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }

    osProfile: {
      computerName: 'web01'
      adminUsername: adminUsername
      adminPassword: adminPassword
      customData: base64(web01CloudInit)

      linuxConfiguration: {
        disablePasswordAuthentication: false
      }
    }

    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }

      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }

    networkProfile: {
      networkInterfaces: [
        {
          id: nicWeb01.id
        }
      ]
    }
  }
}

resource vmWeb02 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: 'vm-web-02'
  location: location

  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }

    osProfile: {
      computerName: 'web02'
      adminUsername: adminUsername
      adminPassword: adminPassword
      customData: base64(web02CloudInit)

      linuxConfiguration: {
        disablePasswordAuthentication: false
      }
    }

    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }

      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }

    networkProfile: {
      networkInterfaces: [
        {
          id: nicWeb02.id
        }
      ]
    }
  }
}

resource vmDb01 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: 'vm-db-01'
  location: location

  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }

    osProfile: {
      computerName: 'db01'
      adminUsername: adminUsername
      adminPassword: adminPassword
      customData: base64(db01CloudInit)

      linuxConfiguration: {
        disablePasswordAuthentication: false
      }
    }

    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }

      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }

    networkProfile: {
      networkInterfaces: [
        {
          id: nicDb01.id
        }
      ]
    }
  }
}

resource vmApp01 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: 'vm-app-01'
  location: location

  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }

    osProfile: {
      computerName: 'app01'
      adminUsername: adminUsername
      adminPassword: adminPassword
      customData: base64(app01CloudInit)

      linuxConfiguration: {
        disablePasswordAuthentication: false
      }
    }

    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }

      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }

    networkProfile: {
      networkInterfaces: [
        {
          id: nicApp01.id
        }
      ]
    }
  }
}

//
// Useful demo outputs
//

output web01PublicIp string = pipWeb01.properties.ipAddress

output web01PrivateIp string = nicWeb01.properties.ipConfigurations[0].properties.privateIPAddress
output web02PrivateIp string = nicWeb02.properties.ipConfigurations[0].properties.privateIPAddress
output db01PrivateIp string = nicDb01.properties.ipConfigurations[0].properties.privateIPAddress
output app01PrivateIp string = nicApp01.properties.ipConfigurations[0].properties.privateIPAddress
