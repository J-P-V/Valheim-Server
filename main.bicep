// Valheim dedikerad server i Azure.
// Knyter ihop nätverk, VM, valfri Key Vault och driftinställningar.
targetScope = 'resourceGroup'

// ---------- Typer ----------

@description('Världsmodifierare, skickas som "-modifier <name> <value>".')
type modifierType = {
  name: 'combat' | 'deathpenalty' | 'resources' | 'raids' | 'portals'
  value: 'veryeasy' | 'easy' | 'hard' | 'veryhard' | 'casual' | 'hardcore' | 'muchless' | 'less' | 'more' | 'muchmore' | 'most' | 'none'
}

@description('Flaggor som skickas som "-setkey <key>".')
type setKeyType = 'nobuildcost' | 'playerevents' | 'passivemobs' | 'nomap'

// ---------- Allmänt ----------

@description('Namnprefix för alla Azure-resurser.')
@minLength(3)
@maxLength(20)
param namePrefix string = 'valheim'

@description('Azure-region. Standard är resursgruppens region.')
param location string = resourceGroup().location

param tags object = {
  project: 'valheim'
}

// ---------- Spelinställningar ----------

@description('Servernamnet som visas i serverlistan.')
@minLength(1)
param serverName string

@description('Världsnamn. Skapas om det inte finns i savedir.')
param worldName string = 'Dedicated'

@description('Lösenord för att ansluta. Minst 5 tecken och får inte innehålla servernamnet.')
@secure()
@minLength(5)
param serverPassword string

@description('UDP-port för spelet. Porten och port+1 används.')
@minValue(1024)
@maxValue(65534)
param gamePort int = 2456

@description('Visa servern i den publika serverlistan.')
param isPublic bool = true

@description('Crossplay via PlayFab-relay. Då behövs inga öppna spelportar, men servern kan inte nås via IP.')
param crossplay bool = false

@description('Svårighetspreset. Tom sträng skickar ingen -preset.')
@allowed(['', 'normal', 'casual', 'easy', 'hard', 'hardcore', 'immersive', 'hammer'])
param preset string = ''

param modifiers modifierType[] = []

param setKeys setKeyType[] = []

@description('Sekunder mellan världssparningar.')
@minValue(60)
param saveInterval int = 1800

@description('Antal automatiska backuper som behålls.')
@minValue(1)
param backups int = 4

@description('Sekunder till första backupen.')
param backupShort int = 7200

@description('Sekunder mellan efterföljande backuper.')
param backupLong int = 43200

@description('Admins, formatet [Plattform]_[UserID], t.ex. Steam_76561198012345678.')
param adminIds string[] = []

@description('Vitlista. Om listan inte är tom spärras alla som inte står med.')
param permittedIds string[] = []

@description('Bannlista.')
param bannedIds string[] = []

// ---------- Infrastruktur ----------

@description('VM-storlek. Standard_B2ms eller Standard_D2as_v5 räcker för en mindre grupp.')
param vmSize string = 'Standard_B2ms'

@description('Datadisk för världar och backuper, i GB.')
@minValue(8)
param dataDiskSizeGb int = 32

@description('Administratörsanvändare för SSH.')
param adminUsername string = 'azureuser'

@description('Publik SSH-nyckel för administratören.')
param adminSshPublicKey string

@description('CIDR som får nå SSH, t.ex. 1.2.3.4/32.')
param adminSourceIp string

@description('DNS-label för publika IP:n. Måste vara unik i regionen.')
param dnsLabel string = toLower('${namePrefix}-${uniqueString(resourceGroup().id)}')

@description('Lagra lösenordet i Key Vault och hämta det vid start, i stället för att lägga det i cloud-init.')
param useKeyVault bool = true

@description('Daglig auto-shutdown i formatet HHmm, t.ex. 0100. Tom sträng = av.')
param autoShutdownTime string = ''

@description('Tidszon för auto-shutdown.')
param autoShutdownTimeZone string = 'W. Europe Standard Time'

// ---------- Härledda värden ----------

var keyVaultName = 'kv-valheim-${take(uniqueString(resourceGroup().id), 10)}'
var keyVaultSecretName = 'valheim-server-password'
var keyVaultUri = useKeyVault ? 'https://${keyVaultName}${environment().suffixes.keyvaultDns}' : ''

var modifierArgs = join(map(modifiers, m => '-modifier ${m.name} ${m.value}'), ' ')
var setKeyArgs = join(map(setKeys, k => '-setkey ${k}'), ' ')

// Läses av systemd via EnvironmentFile. Värden med mellanslag citeras.
var serverEnv = join(
  [
    'SERVER_NAME="${serverName}"'
    'WORLD_NAME="${worldName}"'
    'SERVER_PASSWORD="${useKeyVault ? '' : serverPassword}"'
    'GAME_PORT=${gamePort}'
    'IS_PUBLIC=${isPublic ? 1 : 0}'
    'CROSSPLAY=${crossplay ? 'true' : 'false'}'
    'PRESET=${preset}'
    'MODIFIER_ARGS="${modifierArgs}"'
    'SETKEY_ARGS="${setKeyArgs}"'
    'SAVE_DIR=/srv/valheim-data/saves'
    'SAVE_INTERVAL=${saveInterval}'
    'BACKUPS=${backups}'
    'BACKUP_SHORT=${backupShort}'
    'BACKUP_LONG=${backupLong}'
    'KEYVAULT_URI=${keyVaultUri}'
    'KEYVAULT_SECRET=${keyVaultSecretName}'
  ],
  '\n'
)

var cloudInit = format(
  loadTextContent('cloud-init/valheim.yaml'),
  base64(serverEnv),
  base64(join(adminIds, '\n')),
  base64(join(permittedIds, '\n')),
  base64(join(bannedIds, '\n'))
)

// ---------- Moduler ----------

module network 'modules/network.bicep' = {
  name: 'network'
  params: {
    namePrefix: namePrefix
    location: location
    gamePort: gamePort
    crossplay: crossplay
    adminSourceIp: adminSourceIp
    dnsLabel: dnsLabel
    tags: tags
  }
}

module vm 'modules/vm.bicep' = {
  name: 'vm'
  params: {
    namePrefix: namePrefix
    location: location
    subnetId: network.outputs.subnetId
    publicIpId: network.outputs.publicIpId
    vmSize: vmSize
    dataDiskSizeGb: dataDiskSizeGb
    adminUsername: adminUsername
    adminSshPublicKey: adminSshPublicKey
    cloudInit: cloudInit
    tags: tags
  }
}

// Key Vault skapas efter VM:en eftersom rolltilldelningen behöver VM:ens identitet.
// cloud-init känner redan till vault-URI:n (härledd av namnet) och väntar in rättigheten vid start.
module keyVault 'modules/keyvault.bicep' = if (useKeyVault) {
  name: 'keyvault'
  params: {
    keyVaultName: keyVaultName
    location: location
    serverPassword: serverPassword
    secretName: keyVaultSecretName
    vmPrincipalId: vm.outputs.principalId
    tags: tags
  }
}

module ops 'modules/ops.bicep' = {
  name: 'ops'
  params: {
    vmId: vm.outputs.vmId
    vmName: vm.outputs.vmName
    location: location
    autoShutdownTime: autoShutdownTime
    autoShutdownTimeZone: autoShutdownTimeZone
    tags: tags
  }
}

// ---------- Utdata ----------

output publicIpAddress string = network.outputs.publicIpAddress
output fqdn string = network.outputs.fqdn
output sshCommand string = 'ssh ${adminUsername}@${network.outputs.fqdn}'
output gameConnect string = crossplay
  ? 'Crossplay: anslut med join-koden som skrivs i serverloggen (sudo journalctl -u valheim)'
  : '${network.outputs.fqdn}:${gamePort}'
output keyVaultName string = useKeyVault ? keyVaultName : ''
