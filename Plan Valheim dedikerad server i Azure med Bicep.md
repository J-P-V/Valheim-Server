# Plan: Valheim dedikerad server i Azure med Bicep

Oct 24, 2026 · @John

## Det viktigaste från guiden

- **Två nätverkslägen:** Steam-backend kräver att portintervallet (default 2456–2457) är nåbart från internet. Med `-crossplay` går trafiken via en relay (PlayFab), så ingen portöppning behövs. Porten skiljer ändå servrar åt på samma IP, och crossplay kan inte nås via lokal IP eller loopback.
- **Linux stöds** via `start_server.sh`. Kräver `libatomic1`, `libpulse-dev`, `libpulse0` samt GLIBC ≥ 2.29 och GLIBCXX ≥ 3.4.26. Docker är bara ett alternativ för äldre distar.
- **Kopiera startskriptet**, eftersom originalet skrivs över vid varje uppdatering.
- **Stoppa med CTRL+C (SIGINT)**, annars kan servern fortsätta köra i bakgrunden. Detta styr systemd-konfigurationen.
- **Behörighetsfiler** i save-katalogen: `adminlist.txt`, `bannedlist.txt`, `permittedlist.txt`, med en `[Plattform]_[UserID]` per rad. Står någon i permittedlist spärras alla andra.
- **Startparametrar:** `-name`, `-port`, `-world`, `-password`, `-savedir`, `-public`, `-logFile`, `-saveinterval`, `-backups`, `-backupshort`, `-backuplong`, `-crossplay`, `-instanceid`, `-preset`, `-modifier`, `-setkey`.
- **Default save-path på Linux:** `~/.config/unity3d/IronGate/Valheim`.

### Saker guiden inte täcker (att verifiera)

- Guiden beskriver bara installation via Steam-klienten, inte SteamCMD. Server-app-ID är **896660**, installeras anonymt med `steamcmd +login anonymous +app_update 896660 validate`.
- Protokoll anges inte. Spelet använder **UDP**. Vissa källor nämner även port 2458, vilket bör testas.
- Lösenordskravet (minst 5 tecken, får inte innehålla servernamnet) saknas i guiden.
- Windows-sökvägen i guiden (`../%USERPROFILE%/...`) ser felskriven ut, men är irrelevant på Linux.

## Arkitekturval

**Rekommendation: Ubuntu 24.04-VM med SteamCMD direkt på värden och systemd.** Ubuntu 24.04 har GLIBC 2.39, så Docker-omvägen behövs inte. Det ger enklast felsökning och full kontroll över SIGINT-stoppet.

Bortvalda alternativ:

- **Azure Container Instances:** UDP fungerar, men persistens via Azure Files (SMB) är långsam för världssparning, och graciöst stopp är svårare att styra.
- **Windows-VM:** dyrare licens och mer RAM-overhead utan fördel här.

## Resurser i Bicep

| Modul | Resurser | Kommentar |
| --- | --- | --- |
| `network.bicep` | VNet, subnet, NSG, Public IP (Standard, statisk, DNS-label) | NSG öppnar UDP `port`–`port+1` bara om `crossplay == false`. SSH endast från `adminSourceIp`. |
| `vm.bicep` | NIC, Linux-VM, OS-disk, separat datadisk för `-savedir` | Världar överlever omskapad VM. Storlek t.ex. `Standard_B2ms` eller `D2as_v5` (2 vCPU / 8 GB). |
| `cloud-init/valheim.yaml` | Installation och konfiguration | Laddas via `loadTextContent` + `format` som customData. |
| `keyvault.bicep` (valfri) | Key Vault + managed identity på VM | Lösenordet hämtas vid start i stället för att ligga i customData. |
| `ops.bicep` | Auto-shutdown-schema, ev. Recovery Services Vault eller diskbackup | Shutdown via ACPI → systemd-stopp → SIGINT, så servern hinner spara. |
| `main.bicep` + `main.bicepparam` | Knyter ihop modulerna |  |

## cloud-init

1. Aktivera `multiverse` och i386, acceptera Steam-licensen via debconf och installera `steamcmd libatomic1 libpulse0 libpulse-dev`.
2. Skapa systemanvändaren `valheim`. Formatera och montera datadisken på `/srv/valheim-data` via `fs_setup`/`mounts`.
3. Installera servern: `steamcmd +force_install_dir /opt/valheim +login anonymous +app_update 896660 validate +quit`.
4. Skriv en egen startfil `/opt/valheim-config/start.sh` utanför installationskatalogen så den inte skrivs över. Den sätter `LD_LIBRARY_PATH` och `SteamAppId=892970` enligt Linux-originalet och läser parametrar från `/etc/valheim/server.env`.
5. Skapa systemd-unit `valheim.service`:
   - `ExecStartPre=` kör steamcmd-uppdatering, så servern är patchad vid varje omstart.
   - `KillSignal=SIGINT`, motsvarar guidens CTRL+C.
   - `TimeoutStopSec=120` ger tid för sparning.
   - `Restart=on-failure`.
6. Lägg ut `adminlist.txt`, `permittedlist.txt` och `bannedlist.txt` i savedir från Bicep-parametrar (arrayer joinade med radbrytning).
7. Valfritt: systemd-timer för nattlig omstart (uppdatering och minnesrensning).

## Parametrar (main.bicepparam)

| Parameter | Typ / validering | Default |
| --- | --- | --- |
| `serverName` | string | – |
| `worldName` | string | `Dedicated` |
| `serverPassword` | `@secure()`, `@minLength(5)` | – |
| `gamePort` | int | 2456 |
| `isPublic` | bool | true |
| `crossplay` | bool | false |
| `preset` | `@allowed` Normal/Casual/Easy/Hard/Hardcore/Immersive/Hammer | Normal |
| `modifiers` | array av `{name, value}` | \[\] |
| `setKeys` | array (nobuildcost, playerevents, passivemobs, nomap) | \[\] |
| `saveInterval` | int (s) | 1800 |
| `backups` / `backupShort` / `backupLong` | int / int (s) / int (s) | 4 / 7200 / 43200 |
| `adminIds` / `permittedIds` / `bannedIds` | array | \[\] |
| `vmSize` | string | `Standard_B2ms` |
| `dataDiskSizeGb` | int | 32 |
| `adminSshPublicKey` | string | – |
| `adminSourceIp` | string (CIDR) | – |
| `autoShutdownTime` | string (HHmm) | tom = av |

`@allowed` och validering på preset och modifiers fångar fel före driftsättning, i stället för att servern tyst ignorerar dem.

## Filstruktur

```
valheim-azure/
├─ main.bicep
├─ main.bicepparam
├─ modules/
│  ├─ network.bicep
│  ├─ vm.bicep
│  ├─ keyvault.bicep
│  └─ ops.bicep
├─ cloud-init/
│  └─ valheim.yaml
└─ deploy.ps1          # az deployment group create + utskrift av IP/FQDN
```

## Implementationsordning

1. `network.bicep` + `vm.bicep` med minimal cloud-init. Verifiera SSH och att datadisken är monterad.
2. Lägg till SteamCMD-installation och systemd-tjänst. Verifiera att `journalctl -u valheim` visar "Game server connected".
3. Testa anslutning i båda lägena: Steam (IP:port) och crossplay (join-kod).
4. Lägg till behörighetsfiler, presets och modifiers.
5. Lägg till Key Vault, auto-shutdown och backup.
6. Skriv `deploy.ps1` med what-if-steg (`az deployment group what-if`) före driftsättning.

## Öppna frågor

- [ ] Crossplay eller bara Steam? Avgör om NSG-portar behövs alls.
- [ ] Dygnet runt eller auto-shutdown? En B2ms kostar ca 600–700 kr/mån vid 24/7 (ungefärligt, ej verifierat).
- [ ] `@secure()`-lösenord i customData eller Key Vault?
- [ ] Befintlig värld att importera? Kräver i så fall ett uppladdningssteg till datadisken.

## Källor

- [A Guide to Dedicated Servers – Valheim](https://www.valheimgame.com/support/a-guide-to-dedicated-servers/)
