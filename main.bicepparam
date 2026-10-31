using './main.bicep'

// Hemligheter och miljöspecifika värden läses från miljövariabler.
// deploy.ps1 sätter VALHEIM_SSH_PUBLIC_KEY och VALHEIM_ADMIN_CIDR automatiskt om de saknas.
param serverPassword = readEnvironmentVariable('VALHEIM_PASSWORD')
param adminSshPublicKey = readEnvironmentVariable('VALHEIM_SSH_PUBLIC_KEY')
param adminSourceIp = readEnvironmentVariable('VALHEIM_ADMIN_CIDR')

// ---------- Spel ----------
param serverName = 'Midgard Misfits'
param worldName = 'Misfitheim'
param gamePort = 2456
param isPublic = true
param crossplay = true

// Tom sträng = spelets standard. Alternativ: normal, casual, easy, hard, hardcore, immersive, hammer.
param preset = ''

// Exempel: [{ name: 'combat', value: 'hard' }, { name: 'raids', value: 'none' }]
param modifiers = []

// Exempel: ['nomap', 'passivemobs']
param setKeys = []

param saveInterval = 900
param backups = 96
param backupShort = 7200
param backupLong = 43200

// Formatet är [Plattform]_[UserID], t.ex. 'Steam_76561198012345678'.
param adminIds = ['Steam_76561197987446879']
param permittedIds = []
param bannedIds = []

// ---------- Infrastruktur ----------
param namePrefix = 'valheim'
param vmSize = 'Standard_B2ls_v2'
param dataDiskSizeGb = 32
param adminUsername = 'azureuser'
param useKeyVault = true

// Tom sträng = ingen auto-shutdown. Exempel: '0100' stänger av kl. 01:00.
// param autoShutdownTime = '0000'
param autoShutdownTime = ''
param autoShutdownTimeZone = 'W. Europe Standard Time'
