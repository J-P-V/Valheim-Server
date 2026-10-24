<#
.SYNOPSIS
  Driftsätter Valheim-servern i Azure med Bicep.

.DESCRIPTION
  Skapar resursgruppen, kör what-if och driftsätter main.bicep med main.bicepparam.
  Miljövariabler som används av parameterfilen:
    VALHEIM_PASSWORD        (krävs) serverlösenord, minst 5 tecken
    VALHEIM_SSH_PUBLIC_KEY  (valfri) publik SSH-nyckel, annars läses ~/.ssh/id_ed25519.pub eller id_rsa.pub
    VALHEIM_ADMIN_CIDR      (valfri) CIDR som får nå SSH, annars din publika IP/32

.EXAMPLE
  $env:VALHEIM_PASSWORD = 'hemligt123'
  ./deploy.ps1 -ResourceGroup rg-valheim -Location swedencentral
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [string]$ResourceGroup,

  [string]$Location = 'swedencentral',

  [string]$ParametersFile = (Join-Path $PSScriptRoot 'main.bicepparam'),

  # Kör bara what-if och avsluta.
  [switch]$WhatIfOnly,

  # Hoppa över what-if och bekräftelse.
  [switch]$Force
)

$ErrorActionPreference = 'Stop'

if (-not $env:VALHEIM_PASSWORD) {
  throw 'Sätt miljövariabeln VALHEIM_PASSWORD (minst 5 tecken, får inte innehålla servernamnet).'
}
if ($env:VALHEIM_PASSWORD.Length -lt 5) {
  throw 'VALHEIM_PASSWORD måste vara minst 5 tecken.'
}

if (-not $env:VALHEIM_SSH_PUBLIC_KEY) {
  $candidates = @(
    (Join-Path $HOME '.ssh/id_ed25519.pub'),
    (Join-Path $HOME '.ssh/id_rsa.pub')
  )
  $keyFile = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
  if (-not $keyFile) {
    throw 'Sätt VALHEIM_SSH_PUBLIC_KEY eller skapa en nyckel med: ssh-keygen -t ed25519'
  }
  $env:VALHEIM_SSH_PUBLIC_KEY = (Get-Content $keyFile -Raw).Trim()
  Write-Host "SSH-nyckel: $keyFile"
}

if (-not $env:VALHEIM_ADMIN_CIDR) {
  $myIp = (Invoke-RestMethod -Uri 'https://api.ipify.org').Trim()
  $env:VALHEIM_ADMIN_CIDR = "$myIp/32"
}
Write-Host "SSH tillåts från: $env:VALHEIM_ADMIN_CIDR"

Write-Host "Resursgrupp: $ResourceGroup ($Location)"
az group create --name $ResourceGroup --location $Location --output none
if ($LASTEXITCODE -ne 0) { throw 'Kunde inte skapa resursgruppen.' }

if (-not $Force) {
  Write-Host ''
  Write-Host '--- what-if ---'
  az deployment group what-if --resource-group $ResourceGroup --parameters $ParametersFile
  if ($LASTEXITCODE -ne 0) { throw 'what-if misslyckades.' }
  if ($WhatIfOnly) { return }

  $answer = Read-Host 'Fortsätt med driftsättningen? (j/N)'
  if ($answer -notin @('j', 'J', 'y', 'Y')) {
    Write-Host 'Avbryter.'
    return
  }
}

$deploymentName = "valheim-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Write-Host ''
Write-Host "Driftsätter ($deploymentName)..."
$json = az deployment group create `
  --resource-group $ResourceGroup `
  --name $deploymentName `
  --parameters $ParametersFile `
  --query properties.outputs `
  --output json
if ($LASTEXITCODE -ne 0) { throw 'Driftsättningen misslyckades.' }

$out = $json | ConvertFrom-Json
Write-Host ''
Write-Host "Publik IP:   $($out.publicIpAddress.value)"
Write-Host "FQDN:        $($out.fqdn.value)"
Write-Host "SSH:         $($out.sshCommand.value)"
Write-Host "Anslut:      $($out.gameConnect.value)"
if ($out.keyVaultName.value) {
  Write-Host "Key Vault:   $($out.keyVaultName.value)"
}
Write-Host ''
Write-Host 'Servern installeras nu via cloud-init (ca 5–10 min). Följ förloppet med:'
Write-Host "  $($out.sshCommand.value) 'sudo tail -f /var/log/cloud-init-output.log'"
Write-Host "  $($out.sshCommand.value) 'sudo journalctl -u valheim -f'"
