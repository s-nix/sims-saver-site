<#
.SYNOPSIS
  Sims Saver installer for Windows.

  irm https://sims-saver.nix.uno/install.ps1 | iex

  Installs per-user (no administrator prompt) into
  %LOCALAPPDATA%\Programs\Sims Saver and starts the app.

.PARAMETER Version
  Release tag to install (default: latest). Also read from $env:SIMS_SAVER_VERSION.
.PARAMETER NoLaunch
  Do not start the app afterwards.
.PARAMETER BaseUrl
  Fetch assets from this directory URL instead of the download site (mirrors/tests).
  Also read from $env:SIMS_SAVER_BASE_URL.
#>
[CmdletBinding()]
param(
  [string]$Version = $env:SIMS_SAVER_VERSION,
  [string]$BaseUrl = $env:SIMS_SAVER_BASE_URL,
  [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Site = 'https://sims-saver.nix.uno'

function Say($msg) { Write-Host "==> $msg" -ForegroundColor Green }

if (-not $Version -and $BaseUrl) { throw 'BaseUrl requires -Version as well' }
if (-not $Version) {
  $Version = (Invoke-RestMethod -Headers @{ 'User-Agent' = 'sims-saver-install' } -Uri "$Site/latest-version.txt").Trim()
  if (-not $Version) { throw "Could not determine the latest release from $Site" }
}
$Ver = $Version.TrimStart('v')
$Base = if ($BaseUrl) { $BaseUrl.TrimEnd('/') } else { "$Site/releases/$Version" }
$Asset = "sims-saver_${Ver}_windows_amd64_setup.exe"
Say "Installing Sims Saver $Version"

$Tmp = Join-Path ([IO.Path]::GetTempPath()) ("sims-saver-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Tmp | Out-Null
try {
  Say "Downloading $Asset"
  $exe = Join-Path $Tmp $Asset
  Invoke-WebRequest -UseBasicParsing -Uri "$Base/$Asset" -OutFile $exe
  Invoke-WebRequest -UseBasicParsing -Uri "$Base/checksums.txt" -OutFile (Join-Path $Tmp 'checksums.txt')

  $line = Get-Content (Join-Path $Tmp 'checksums.txt') | Where-Object { $_ -match "\s\*?$([regex]::Escape($Asset))$" }
  if (-not $line) { throw "No checksum listed for $Asset" }
  $want = ($line -split '\s+')[0].ToLower()
  $got = (Get-FileHash -Algorithm SHA256 $exe).Hash.ToLower()
  if ($got -ne $want) { throw "Checksum mismatch for $Asset" }
  Say "Verified $Asset"

  Say 'Running installer'
  # NSIS silent install; per-user scope needs no elevation.
  $p = Start-Process -FilePath $exe -ArgumentList '/S' -Wait -PassThru
  if ($p.ExitCode -ne 0) { throw "Installer exited with code $($p.ExitCode)" }

  $installed = Join-Path $env:LOCALAPPDATA 'Programs\Sims Saver\sims-saver.exe'
  if (-not (Test-Path $installed)) { throw "Install finished but $installed was not found" }
  Say "Installed $installed"
  Say 'Done. Sims Saver runs in the system tray; it will walk you through setup on first launch.'
  if (-not $NoLaunch) { Say 'Launching'; Start-Process -FilePath $installed }
}
finally {
  Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
}
