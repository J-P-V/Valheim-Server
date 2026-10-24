# Valheim dedikerad server i Azure (Bicep)

Ubuntu 24.04-VM med SteamCMD och systemd, driftsatt med Bicep. Bakgrund och designval finns i
[planen](Plan%20Valheim%20dedikerad%20server%20i%20Azure%20med%20Bicep.md).

## Förutsättningar

- Azure CLI med Bicep (`az bicep version`)
- Inloggad: `az login` och rätt prenumeration vald
- En SSH-nyckel (`ssh-keygen -t ed25519`)

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

## Nätverk

- Utan crossplay öppnas UDP `gamePort`–`gamePort+1` från internet. Anslut med `FQDN:port`.
- Med `crossplay = true` öppnas inga spelportar. Join-koden skrivs i serverloggen.
- SSH tillåts bara från `adminSourceIp`.
