param location string

// 1. Aplikacijų saugos grupės (ASG)
resource asgWeb 'Microsoft.Network/applicationSecurityGroups@2023-09-01' = {
  name: 'asg-web-servers'
  location: location
}

resource asgDB 'Microsoft.Network/applicationSecurityGroups@2023-09-01' = {
  name: 'asg-db-servers'
  location: location
}

// 2. Tinklo saugos grupė (NSG)
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'nsg-projekto-saugumas'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowWebToDB'
        properties: {
          priority: 100
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
    ]
  }
}

// 4. Sukuriame kelias NIC plokštes (3 Web ir 2 DB)
// Naudojame kilpą (loop), kad kodas būtų švaresnis
resource nicWeb 'Microsoft.Network/networkInterfaces@2023-09-01' = [for i in range(1, 3): {
  name: 'nic-web-0${i}'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: { id: vnet.properties.subnets[0].id }
          applicationSecurityGroups: [ { id: asgWeb.id } ]
        }
      }
    ]
  }
}]

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
