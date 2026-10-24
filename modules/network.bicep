// Nätverk: VNet, subnet, NSG och publik IP för Valheim-servern.
@description('Namnprefix för resurserna.')
param namePrefix string

@description('Azure-region.')
param location string

@description('UDP-port för spelet. Porten och port+1 öppnas om crossplay är avstängt.')
param gamePort int

@description('Om true går speltrafiken via PlayFab-relay och inga spelportar öppnas i NSG.')
param crossplay bool

@description('CIDR (t.ex. 1.2.3.4/32) som får nå SSH.')
param adminSourceIp string

@description('DNS-label för den publika IP-adressen (blir <label>.<region>.cloudapp.azure.com).')
param dnsLabel string

param tags object = {}

var gameRule = [
  {
    name: 'allow-valheim-udp'
    properties: {
      priority: 100
      direction: 'Inbound'
      access: 'Allow'
      protocol: 'Udp'
      sourceAddressPrefix: 'Internet'
      sourcePortRange: '*'
      destinationAddressPrefix: '*'
      destinationPortRange: '${gamePort}-${gamePort + 1}'
      description: 'Valheim Steam-backend (spel + query)'
    }
  }
]

var sshRule = [
  {
    name: 'allow-ssh-admin'
    properties: {
      priority: 110
      direction: 'Inbound'
      access: 'Allow'
      protocol: 'Tcp'
      sourceAddressPrefix: adminSourceIp
      sourcePortRange: '*'
      destinationAddressPrefix: '*'
      destinationPortRange: '22'
      description: 'SSH endast från administratörens IP'
    }
  }
]

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${namePrefix}-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: concat(sshRule, crossplay ? [] : gameRule)
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: '${namePrefix}-vnet'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: ['10.60.0.0/24']
    }
    subnets: [
      {
        name: 'game'
        properties: {
          addressPrefix: '10.60.0.0/26'
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

resource publicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: '${namePrefix}-pip'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    dnsSettings: {
      domainNameLabel: dnsLabel
    }
  }
}

output subnetId string = vnet.properties.subnets[0].id
output publicIpId string = publicIp.id
output publicIpAddress string = publicIp.properties.ipAddress
output fqdn string = publicIp.properties.dnsSettings.fqdn
