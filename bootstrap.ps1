[CmdletBinding()]
param([switch]$Repair)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$ReleaseUrl = 'https://github.com/Zouzitou/rcn-fpvskydive/releases/download/v0.1.56/rcn-fpvskydive-v0.1.56.zip'
$ExpectedSha256 = '8D7CFFD221379D7F1810A0F69AAF95C66288322B86E567A54090AC8022E194B1'
$SourceRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
  $FetchRoot = Join-Path $env:TEMP ('rcn-fpv-fetch-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $FetchRoot | Out-Null
  $Archive = Join-Path $FetchRoot 'release.zip'
  Write-Host '  RCN FPV SKYDIVE  •  Fetching verified release…' -ForegroundColor DarkYellow
  Invoke-WebRequest -Uri $ReleaseUrl -OutFile $Archive
  $ActualSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $Archive).Hash
  if ($ActualSha256 -ne $ExpectedSha256) { throw 'Release verification failed. Nothing was installed.' }
  Expand-Archive -LiteralPath $Archive -DestinationPath $FetchRoot -Force
  $SourceRoot = $FetchRoot
}
& (Join-Path $SourceRoot 'install-app.ps1') -SourceRoot $SourceRoot -BridgeSource (Join-Path $SourceRoot 'bin\rcn-bridge.exe') -InstallMode 'verified-release'
