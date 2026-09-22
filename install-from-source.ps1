[CmdletBinding()]
param([string]$Ref = 'v0.1.67')

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Repository = 'Zouzitou/rcn-fpvskydive'
if ($Ref -notmatch '^v\d+\.\d+\.\d+$') { throw 'Ref must be a release tag such as v0.1.46. Nothing was installed.' }
$Root = Join-Path $env:LOCALAPPDATA 'RCN-FPVSkyDive'
$CacheRoot = Join-Path $Root 'source-cache'
$BuildId = 'build-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
$BuildRoot = Join-Path $CacheRoot $BuildId
$Archive = Join-Path $BuildRoot 'source.zip'
$BuildLog = Join-Path $BuildRoot 'build.log'

$InstallerUseAnsi = $false
try { $InstallerUseAnsi = [bool]$Host.UI.SupportsVirtualTerminal } catch { }
function Write-SourceUi {
  param([string]$Text, [string]$Tone = 'Orange')
  $code = if ($Tone -eq 'Green') { '38;5;114' } elseif ($Tone -eq 'Red') { '38;5;203' } elseif ($Tone -eq 'Dim') { '38;5;245' } else { '38;5;208' }
  if ($InstallerUseAnsi) { Write-Host ("`e[{0}m{1}`e[0m" -f $code, $Text) }
  else {
    $fallback = if ($Tone -eq 'Green') { 'Green' } elseif ($Tone -eq 'Red') { 'Red' } elseif ($Tone -eq 'Dim') { 'DarkGray' } else { 'DarkYellow' }
    Write-Host $Text -ForegroundColor $fallback
  }
}
function Show-Step { param([int]$Number, [string]$Message, [string]$Detail); Write-Progress -Activity 'RCN FPV SkyDive source installer' -Status $Message -PercentComplete ($Number * 20); Write-SourceUi ("  [{0}/5]  {1}" -f $Number, $Message); if ($Detail) { Write-SourceUi ("         {0}" -f $Detail) 'Dim' } }
try { Clear-Host } catch { }
Write-SourceUi '╔══════════════════════════════════════════════════════╗'
Write-SourceUi '║                 RCN FPV SKYDIVE                      ║'
Write-SourceUi '╚══════════════════════════════════════════════════════╝'
Write-SourceUi '  Transparent local source build  •  no driver changes' 'Dim'
Write-Host ''

Show-Step 1 'Checking the local Rust build toolchain' 'No downloads or system changes from this installer.'
$CargoCommand = Get-Command cargo -ErrorAction SilentlyContinue
if ($null -eq $CargoCommand) { throw 'Rust Cargo was not found. Install the stable Rust toolchain from https://rustup.rs, restart PowerShell, then run this command again. Nothing was installed.' }
& cargo --version | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Cargo could not run. Nothing was installed.' }

Show-Step 2 "Fetching transparent source archive for $Ref" 'Downloading only the public, release-tagged source.'
New-Item -ItemType Directory -Force -Path $BuildRoot | Out-Null
$SourceUrl = "https://github.com/$Repository/archive/refs/tags/$Ref.zip"
Invoke-WebRequest -Uri $SourceUrl -OutFile $Archive
Expand-Archive -LiteralPath $Archive -DestinationPath $BuildRoot -Force
$SourceRoot = Get-ChildItem -LiteralPath $BuildRoot -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'rust-bridge\Cargo.toml') } | Select-Object -First 1 -ExpandProperty FullName
if ([string]::IsNullOrWhiteSpace($SourceRoot)) { throw "The $Ref archive did not contain the expected Rust project." }

Show-Step 3 'Building the optimized native bridge locally' 'Compiler details are kept private in the local build log.'
$Manifest = Join-Path $SourceRoot 'rust-bridge\Cargo.toml'
& cargo build --locked --release --manifest-path $Manifest *> $BuildLog
if ($LASTEXITCODE -ne 0) { throw 'Rust source build failed. Your existing installation was not changed.' }
$Bridge = Join-Path $SourceRoot 'rust-bridge\target\release\rcn-bridge.exe'
if (-not (Test-Path -LiteralPath $Bridge -PathType Leaf)) { throw 'Rust completed without producing rcn-bridge.exe. Your existing installation was not changed.' }
$BridgeHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Bridge).Hash
Write-SourceUi ("         Local bridge SHA-256: {0}" -f $BridgeHash) 'Dim'

& (Join-Path $SourceRoot 'install-app.ps1') -SourceRoot $SourceRoot -BridgeSource $Bridge -InstallMode "source-build:$Ref" -SourceBuild
Write-SourceUi '     Source and private compiler log were retained locally for inspection.' 'Dim'
