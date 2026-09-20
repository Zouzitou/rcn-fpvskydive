[CmdletBinding()]
param([switch]$Repair)
$ErrorActionPreference = 'Stop'
$Root = Join-Path $env:LOCALAPPDATA 'RCN-FPVSkyDive'
$App = Join-Path $Root 'app'
New-Item -ItemType Directory -Force -Path $App,(Join-Path $Root '.venv'),(Join-Path $Root 'drivers'),(Join-Path $Root 'logs'),(Join-Path $Root 'state') | Out-Null
Write-Host "RCN FPV SkyDive installer: preparing per-user environment at $Root"
if (-not (Get-Command py -ErrorAction SilentlyContinue)) { throw 'Python 3.9+ is required. Install it from python.org and rerun.' }
py -3 -m venv (Join-Path $Root '.venv')
$Py = Join-Path $Root '.venv\Scripts\python.exe'
& $Py -m pip install --disable-pip-version-check -r (Join-Path $PSScriptRoot 'requirements.lock')
Copy-Item -Recurse -Force (Join-Path $PSScriptRoot 'src') $App
Copy-Item -Force (Join-Path $PSScriptRoot 'pyproject.toml') $App
& $Py -m pip install --disable-pip-version-check --no-deps $App
@{ state='installed'; version='0.1.0'; timestamp=(Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json | Set-Content (Join-Path $Root 'state\health.json')
Write-Host 'Environment prepared. Hardware/driver validation remains required before READY.'
