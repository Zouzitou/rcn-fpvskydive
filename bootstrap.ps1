[CmdletBinding()]
param([switch]$Repair)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$ReleaseUrl = 'https://github.com/Zouzitou/rcn-fpvskydive/releases/download/v0.1.58/rcn-fpvskydive-v0.1.58.zip'
$ExpectedSha256 = 'A1739549904D479C944306A00ACFB9A67C9C727F4F9EAD3DEF217B38269600FF'
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
