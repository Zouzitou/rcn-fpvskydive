[CmdletBinding()]
param([switch]$Repair)
$ErrorActionPreference = 'Stop'
$ReleaseUrl = 'https://github.com/Zouzitou/rcn-fpvskydive/releases/download/v0.1.10/rcn-fpvskydive-v0.1.10.zip'
$ExpectedSha256 = '978C3E9BDF090265A677DFC998EDDBFB3239AF16DE770E6BF20BD1C67BC8CC94'
$SourceRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
  $FetchRoot = Join-Path $env:TEMP ('rcn-fpv-fetch-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $FetchRoot | Out-Null
  $Archive = Join-Path $FetchRoot 'release.zip'
  Invoke-WebRequest -Uri $ReleaseUrl -OutFile $Archive
  $ActualSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $Archive).Hash
  if ($ActualSha256 -ne $ExpectedSha256) { throw "Release hash mismatch. Expected $ExpectedSha256, got $ActualSha256." }
  Expand-Archive -LiteralPath $Archive -DestinationPath $FetchRoot -Force
  $SourceRoot = $FetchRoot
}
$Root = Join-Path $env:LOCALAPPDATA 'RCN-FPVSkyDive'
$App = Join-Path $Root 'app'
New-Item -ItemType Directory -Force -Path $App,(Join-Path $Root '.venv'),(Join-Path $Root 'drivers'),(Join-Path $Root 'logs'),(Join-Path $Root 'state') | Out-Null
Write-Host "RCN FPV SkyDive installer: preparing per-user environment at $Root"
if (-not (Get-Command py -ErrorAction SilentlyContinue)) { throw 'Python 3.9+ is required. Install it from python.org and rerun.' }
py -3 -m venv (Join-Path $Root '.venv')
$Py = Join-Path $Root '.venv\Scripts\python.exe'
& $Py -m pip install --disable-pip-version-check -r (Join-Path $SourceRoot 'requirements.lock')
Copy-Item -Recurse -Force (Join-Path $SourceRoot 'src') $App
Copy-Item -Force (Join-Path $SourceRoot 'pyproject.toml') $App
Copy-Item -Force (Join-Path $SourceRoot 'startup.ps1') (Join-Path $Root 'startup.ps1')
& $Py -m pip install --disable-pip-version-check --no-deps $App
@{ state='installed'; version='0.1.0'; timestamp=(Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json | Set-Content (Join-Path $Root 'state\health.json')
Write-Host 'Environment prepared. Hardware/driver validation remains required before READY.'
