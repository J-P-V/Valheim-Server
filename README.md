# Valheim dedikerad server i Azure (Bicep)

Ubuntu 24.04-VM med SteamCMD och systemd, driftsatt med Bicep. Bakgrund och designval finns i
[planen](Plan%20Valheim%20dedikerad%20server%20i%20Azure%20med%20Bicep.md).

## Förutsättningar

### Verktyg på din dator

| Verktyg | Krav | Installation (Windows) |
| --- | --- | --- |
| PowerShell 7 | 7.1 eller senare för `Read-Host -MaskInput`. 5.1 fungerar med SecureString-varianten. | `winget install Microsoft.PowerShell` |
| Azure CLI | 2.60 eller senare (stöd för `.bicepparam` med `readEnvironmentVariable`) | `winget install Microsoft.AzureCLI` |
| Bicep CLI | 0.30 eller senare. Installeras och uppdateras via Azure CLI. | `az bicep install` eller `az bicep upgrade` |
| OpenSSH-klient | För `ssh-keygen` och inloggning på servern | Ingår i Windows 10/11. Annars: `Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0` |
| Git | Valfritt, för att klona och versionshantera | `winget install Git.Git` |

Kontrollera versionerna:

```powershell
$PSVersionTable.PSVersion
az version
az bicep version
ssh -V
```

På macOS och Linux installeras Azure CLI enligt
[Microsofts guide](https://learn.microsoft.com/cli/azure/install-azure-cli) och PowerShell 7 via
`brew install powershell` respektive distributionens paket. `deploy.ps1` kräver PowerShell men
Bicep-filerna kan även driftsättas direkt med `az deployment group create`.

### SSH-nyckel

`deploy.ps1` letar efter `~/.ssh/id_ed25519.pub` eller `~/.ssh/id_rsa.pub`. Skapa en nyckel om du
saknar en:

```powershell
ssh-keygen -t ed25519 -C "valheim"
```

Vill du använda en annan nyckel, sätt `VALHEIM_SSH_PUBLIC_KEY` till innehållet i `.pub`-filen.

### Azure-konto och inloggning

```powershell
az login
az account list --output table
az account set --subscription "<namn eller id>"
```

Behörigheter som behövs i prenumerationen eller resursgruppen:

- **Contributor** för att skapa resurserna.
- **User Access Administrator** eller **Owner** när `useKeyVault = true`, eftersom
  `modules/keyvault.bicep` tilldelar VM:en rollen Key Vault Secrets User. Med bara Contributor
  misslyckas rolltilldelningen. Sätt då `useKeyVault = false` i `main.bicepparam`, så läggs lösenordet
  i cloud-init i stället.

### Resursproviders och kvoter

Nya prenumerationer har inte alltid alla providers registrerade. Kontrollera och registrera vid behov:

```powershell
az provider show --namespace Microsoft.Compute --query registrationState
az provider show --namespace Microsoft.Network --query registrationState
az provider show --namespace Microsoft.KeyVault --query registrationState
az provider show --namespace Microsoft.DevTestLab --query registrationState   # krävs för auto-shutdown
az provider register --namespace Microsoft.DevTestLab
```

VM-storleken `Standard_B2ms` kräver 2 vCPU av kvoten för B-serien i vald region. Kontrollera med:

```powershell
az vm list-usage --location swedencentral --query "[?contains(name.value, 'standardBSFamily')]" --output table
```

Är kvoten 0 begär du en höjning i portalen under Prenumeration, Användning och kvoter, eller
byter `vmSize` till en storlek du har kvot för.

### Nätverk på din sida

- `deploy.ps1` hämtar din publika IP från api.ipify.org och tillåter SSH bara därifrån. Byter
  din IP måste NSG-regeln uppdateras, enklast genom att köra `deploy.ps1` igen.
- Utan crossplay måste Valheim-klienten nå UDP `gamePort` och `gamePort+1` utåt. Det är normalt
  öppet i hemmanätverk.

### Kostnad

En `Standard_B2ms` med två StandardSSD-diskar och statisk publik IP kostar ungefär 600–700 kr per
månad vid dygnet runt-drift i Sweden Central. Auto-shutdown via `autoShutdownTime` sänker
beräkningskostnaden, men diskar och IP debiteras även när VM:en är avstängd. Siffran är ungefärlig
och bör kontrolleras i
[Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/).

## Driftsätt

```powershell
# Lösenordet skrivs maskerat och hamnar inte i kommandohistoriken (PowerShell 7.1+)
$env:VALHEIM_PASSWORD = Read-Host -MaskInput 'Serverlösenord'
./deploy.ps1 -ResourceGroup rg-valheim -Location swedencentral
```

Om `VALHEIM_PASSWORD` inte är satt frågar `deploy.ps1` efter lösenordet på samma sätt.

I Windows PowerShell 5.1 saknas `-MaskInput`. Använd SecureString i stället:

```powershell
$secure = Read-Host -AsSecureString 'Serverlösenord'
$env:VALHEIM_PASSWORD = [System.Net.NetworkCredential]::new('', $secure).Password
```

Miljövariabeln lever bara i den aktuella sessionen. Töm den efteråt med
`Remove-Item Env:VALHEIM_PASSWORD`. Samma mönster fungerar för `VALHEIM_SSH_PUBLIC_KEY`
och `VALHEIM_ADMIN_CIDR`, men de är inte hemliga och kan sättas i klartext.

Skriptet kör `what-if` först och frågar innan det driftsätter. Justera servernamn, värld,
preset, modifiers och adminlista i `main.bicepparam`.

## Filer

| Fil | Innehåll |
| --- | --- |
| `main.bicep` | Parametrar, validering, ihopsättning av cloud-init och moduler |
| `main.bicepparam` | Dina värden. Hemligheter läses från miljövariabler |
| `modules/network.bicep` | VNet, NSG, publik IP med DNS-label |
| `modules/vm.bicep` | Ubuntu-VM, datadisk, managed identity |
| `modules/keyvault.bicep` | Key Vault med lösenordet, läsrätt för VM:en (valfri, `useKeyVault`) |
| `modules/ops.bicep` | Auto-shutdown (valfri, `autoShutdownTime`) |
| `cloud-init/valheim.yaml` | Installation, startskript, systemd-tjänst |
| `deploy.ps1` | Driftsättning med what-if |

## På servern

```bash
sudo journalctl -u valheim -f          # serverlogg
sudo systemctl restart valheim         # omstart, uppdaterar servern via steamcmd först
sudo tail -f /var/log/cloud-init-output.log   # installationslogg vid första start
```

- Spelinstallation: `/opt/valheim`
- Startskript och konfiguration: `/opt/valheim-config/`, `/etc/valheim/server.env`
- Världar, backuper och behörighetsfiler: `/srv/valheim-data/saves` (egen datadisk)

Tjänsten stoppas med SIGINT, så `systemctl stop`, omstart av VM:en och auto-shutdown låter
servern spara världen innan den avslutas.

### Installation och datadisk

- LUN 0 hittas via `/dev/disk/azure/data/by-lun/0` (NVMe) eller
  `/dev/disk/azure/scsi1/lun0` (SCSI). Det fungerar även med NVMe-baserade VM-storlekar som
  `Standard_D2als_v6`.
- Bara en disk utan partitions- eller filsystemsignaturer formateras. En befintlig ext4-disk
  återanvänds; andra format och motstridiga monteringar stoppar installationen med ett fel.
- Tjänsten kontrollerar att `/srv/valheim-data` är en monteringspunkt innan den uppdaterar
  eller startar spelet. Den ska inte skriva världar till OS-disken om datadisken saknas.
- SteamCMD körs en gång vid tjänstestart. Starten får ta upp till 30 minuter för installation,
  uppdatering och väntan på Key Vault-behörigheter. Key Vault-anrop har egna tidsgränser.
- Cloud-inits slutmeddelande är inte ett installationskvitto. Kontrollera både
  `sudo cloud-init status --long` och `sudo systemctl status valheim`.

Ändringar i cloud-init gäller vid första starten av en ny VM. En vanlig Bicep-driftsättning
installerar inte om en befintlig VM. Vid reparation av en befintlig server: säkerhetskopiera
konfiguration och världar, uppdatera berörda skript och tjänstefilen, kör
`sudo systemctl daemon-reload` och starta om tjänsten. Kör inte om hela cloud-init för att
uppdatera en redan installerad server.

### Behörighetslistor och anslutningskontroll

En icke-tom `permittedlist.txt` tillåter bara listade plattforms-ID:n, även om spelaren har rätt
lösenord. Steam-poster måste använda det numeriska SteamID64, exempelvis
`Steam_76561198012345678`, inte ett visningsnamn eller en profilalias. Använd spelarens faktiska
plattforms-ID från spelet eller anslutningsloggen; gissa inte ett konto från ett namn.

Med crossplay ska loggen visa att sessionen är aktiv och har en join-kod. Koden kan ändras
vid omstart. En aktiv systemd-tjänst ensam bevisar inte att en spelklient kan ansluta. Testa
join-koden med en tillåten spelare och kontrollera anslutningsloggen.

## Nätverk

- Utan crossplay öppnas UDP `gamePort`–`gamePort+1` från internet. Anslut med `FQDN:port`.
- Med `crossplay = true` öppnas inga spelportar. Anslut via join-koden i serverloggen,
  serverlistan eller publik IP och port. Lokal IP och loopback fungerar inte med crossplay.
- SSH tillåts bara från `adminSourceIp`.

Se även [Valheims officiella serverguide](https://www.valheimgame.com/support/a-guide-to-dedicated-servers/).
