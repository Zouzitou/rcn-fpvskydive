[CmdletBinding()]
param([string]$Ref = 'v0.1.47')

$ErrorActionPreference = 'Stop'
$Repository = 'Zouzitou/rcn-fpvskydive'
if ($Ref -notmatch '^v\d+\.\d+\.\d+$') { throw 'Ref must be a release tag such as v0.1.46. Nothing was installed.' }
$Root = Join-Path $env:LOCALAPPDATA 'RCN-FPVSkyDive'
$CacheRoot = Join-Path $Root 'source-cache'
$BuildId = 'build-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
$BuildRoot = Join-Path $CacheRoot $BuildId
$Archive = Join-Path $BuildRoot 'source.zip'
function Show-Step { param([int]$Number, [string]$Message); Write-Progress -Activity 'RCN FPV SkyDive source installer' -Status $Message -PercentComplete ($Number * 20); Write-Host "[$Number/5] $Message" }

Show-Step 1 'Checking the local Rust build toolchain'
$CargoCommand = Get-Command cargo -ErrorAction SilentlyContinue
if ($null -eq $CargoCommand) { throw 'Rust Cargo was not found. Install the stable Rust toolchain from https://rustup.rs, restart PowerShell, then run this command again. Nothing was installed.' }
& cargo --version
if ($LASTEXITCODE -ne 0) { throw 'Cargo could not run. Nothing was installed.' }

Show-Step 2 "Fetching transparent source archive for $Ref"
New-Item -ItemType Directory -Force -Path $BuildRoot | Out-Null
$SourceUrl = "https://github.com/$Repository/archive/refs/tags/$Ref.zip"
Invoke-WebRequest -Uri $SourceUrl -OutFile $Archive
Write-Host "Saved source archive to $Archive"
Expand-Archive -LiteralPath $Archive -DestinationPath $BuildRoot -Force
$SourceRoot = Get-ChildItem -LiteralPath $BuildRoot -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'rust-bridge\Cargo.toml') } | Select-Object -First 1 -ExpandProperty FullName
if ([string]::IsNullOrWhiteSpace($SourceRoot)) { throw "The $Ref archive did not contain the expected Rust project." }

Show-Step 3 'Building the optimized native bridge locally'
$Manifest = Join-Path $SourceRoot 'rust-bridge\Cargo.toml'
& cargo build --locked --release --manifest-path $Manifest
if ($LASTEXITCODE -ne 0) { throw 'Rust source build failed. Your existing installation was not changed.' }
$Bridge = Join-Path $SourceRoot 'rust-bridge\target\release\rcn-bridge.exe'
if (-not (Test-Path -LiteralPath $Bridge -PathType Leaf)) { throw 'Rust completed without producing rcn-bridge.exe. Your existing installation was not changed.' }
$BridgeHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Bridge).Hash
Write-Host "Locally built bridge SHA-256: $BridgeHash"

Show-Step 4 'Installing the locally built bridge'
& (Join-Path $SourceRoot 'install-app.ps1') -SourceRoot $SourceRoot -BridgeSource $Bridge -InstallMode "source-build:$Ref"

Show-Step 5 'Keeping the build source available for inspection'
Write-Progress -Activity 'RCN FPV SkyDive source installer' -Completed
Write-Host 'Source build installation complete.'
Write-Host "Inspectable source is retained at: $SourceRoot"
