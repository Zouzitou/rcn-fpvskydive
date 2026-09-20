[CmdletBinding()]
param([switch]$Repair)
$ErrorActionPreference = 'Stop'
$ReleaseUrl = 'https://github.com/Zouzitou/rcn-fpvskydive/releases/download/v0.1.12/rcn-fpvskydive-v0.1.12.zip'
$ExpectedSha256 = '4F8E6A25DAA3A80738C440298C2EF9312EF59DA89305D9CAC40D22F6768C3ECC'
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
$PackageVersion = (& $Py -c "import rcn_fpv; print(rcn_fpv.__version__)").Trim()
@{ state='installed'; version=$PackageVersion; timestamp=(Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json | Set-Content (Join-Path $Root 'state\health.json')
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'startup.ps1') -Action install
Write-Host 'Environment prepared. Hardware/driver validation remains required before READY.'
