[CmdletBinding()]
param([switch]$Repair)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$ReleaseUrl = 'https://github.com/Zouzitou/rcn-fpvskydive/releases/download/v0.1.85/rcn-fpvskydive-v0.1.85.zip'
$ExpectedSha256 = '3C994E771C4531C239CA324CA26E9437D2CA22748D2191BDDA924CC29CE0C549'
$SourceRoot = if ($Repair) { $null } else { $PSScriptRoot }
if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
  $FetchRoot = Join-Path $env:TEMP ('rcn-fpv-fetch-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $FetchRoot | Out-Null
  $Archive = Join-Path $FetchRoot 'release.zip'
  Write-Host '  RCN FPV SKYDIVE  -  Fetching verified release...' -ForegroundColor DarkYellow
  Invoke-WebRequest -Uri $ReleaseUrl -OutFile $Archive
  $ActualSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $Archive).Hash
  if ($ActualSha256 -ne $ExpectedSha256) { throw 'Release verification failed. Nothing was installed.' }
  Expand-Archive -LiteralPath $Archive -DestinationPath $FetchRoot -Force
  $SourceRoot = $FetchRoot
}
& (Join-Path $SourceRoot 'install-app.ps1') -SourceRoot $SourceRoot -BridgeSource (Join-Path $SourceRoot 'bin\rcn-bridge.exe') -InstallMode 'verified-release'
