$Ref = 'v0.1.79'

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Repository = 'Zouzitou/rcn-fpvskydive'
if ($Ref -notmatch '^v\d+\.\d+\.\d+$') { throw 'Ref must be a release tag such as v0.1.46. Nothing was installed.' }
$SourceUrl = 'https://github.com/Zouzitou/rcn-fpvskydive/releases/download/v0.1.79/rcn-fpvskydive-v0.1.79-source.zip'
$ExpectedSourceSha256 = 'E52AFE5B6770076121DE242FFFA527EAB0A2225708924B377C0CBC4811837EEC'
$PinnedRef = [regex]::Match($SourceUrl, '/download/(v\d+\.\d+\.\d+)/').Groups[1].Value
if ([string]::IsNullOrWhiteSpace($PinnedRef) -or $Ref -ne $PinnedRef) { throw 'This source installer only builds its own verified release tag. Download the matching installer for another version.' }
$Root = Join-Path $env:LOCALAPPDATA 'RCN-FPVSkyDive'
$CacheRoot = Join-Path $Root 'source-cache'
$BuildId = 'build-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
$BuildRoot = Join-Path $CacheRoot $BuildId
$Archive = Join-Path $BuildRoot 'source.zip'
$BuildLog = Join-Path $BuildRoot 'build.log'

function Enable-PrivateCargoPaths {
  $previous = $env:CARGO_ENCODED_RUSTFLAGS
  $remap = "--remap-path-prefix=$env:USERPROFILE=<USERPROFILE>"
  $env:CARGO_ENCODED_RUSTFLAGS = if ([string]::IsNullOrEmpty($previous)) { $remap } else { $previous + [char]0x1f + $remap }
  return $previous
}

function Restore-CargoPaths {
  param([AllowEmptyString()][string]$Previous)
  if ($null -eq $Previous) { Remove-Item Env:CARGO_ENCODED_RUSTFLAGS -ErrorAction SilentlyContinue }
  else { $env:CARGO_ENCODED_RUSTFLAGS = $Previous }
}

function Assert-PrivateArtifact {
  param([Parameter(Mandatory = $true)][string]$Path)
  $patterns = @($env:USERNAME) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  foreach ($pattern in $patterns) {
    & rg -a -i -q --fixed-strings -- $pattern $Path
    if ($LASTEXITCODE -eq 0) { throw 'The local build contains a private build identity. Your existing installation was not changed.' }
    if ($LASTEXITCODE -gt 1) { throw 'Could not inspect the local build for private build identities.' }
  }
}

$InstallerUseAnsi = $false
try { $InstallerUseAnsi = [bool]$Host.UI.SupportsVirtualTerminal } catch { }
function Write-SourceUi {
  param(
    [Parameter(Mandatory = $true, Position = 0)][AllowEmptyString()][string]$Text,
    [Parameter(Position = 1)][string]$Tone = 'Orange'
  )
  $code = if ($Tone -eq 'Green') { '38;5;114' } elseif ($Tone -eq 'Red') { '38;5;203' } elseif ($Tone -eq 'Dim') { '38;5;245' } else { '38;5;208' }
  if ($InstallerUseAnsi) { Write-Host (([char]27 + "[{0}m{1}" + [char]27 + '[0m') -f $code, $Text) }
  else {
    $fallback = if ($Tone -eq 'Green') { 'Green' } elseif ($Tone -eq 'Red') { 'Red' } elseif ($Tone -eq 'Dim') { 'DarkGray' } else { 'DarkYellow' }
    Write-Host $Text -ForegroundColor $fallback
  }
}
function Show-Step { param([int]$Number, [string]$Message, [string]$Detail); Write-Progress -Activity 'RCN FPV SkyDive' -Status $Message -PercentComplete ($Number * 20); Write-SourceUi ("  [{0}/5]  {1}" -f $Number, $Message); if ($Detail) { Write-SourceUi ("         {0}" -f $Detail) 'Dim' } }
try { Clear-Host } catch { }
Write-SourceUi -Text '+------------------------------------------------------+'
Write-SourceUi -Text '|                 RCN FPV SKYDIVE                      |'
Write-SourceUi -Text '+------------------------------------------------------+'
Write-SourceUi -Text '  Building FPV SkyDive from source' -Tone 'Dim'
Write-Host ''

Show-Step 1 'Checking Rust' 'Making sure this computer can build the bridge.'
$CargoCommand = Get-Command cargo -ErrorAction SilentlyContinue
if ($null -eq $CargoCommand) { throw 'Rust Cargo was not found. Install the stable Rust toolchain from https://rustup.rs, restart PowerShell, then run this command again. Nothing was installed.' }
& cargo --version | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Cargo could not run. Nothing was installed.' }

Show-Step 2 "Downloading source $Ref" 'Checking the downloaded source before building it.'
New-Item -ItemType Directory -Force -Path $BuildRoot | Out-Null
Invoke-WebRequest -Uri $SourceUrl -OutFile $Archive
$ActualSourceSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $Archive).Hash
if ($ActualSourceSha256 -ne $ExpectedSourceSha256) { throw 'Source verification failed. Your existing installation was not changed.' }
$SourceRoot = Join-Path $BuildRoot 'source'
Expand-Archive -LiteralPath $Archive -DestinationPath $SourceRoot -Force
if (-not (Test-Path -LiteralPath (Join-Path $SourceRoot 'rust-bridge\Cargo.toml'))) { throw "The $Ref source package did not contain the expected Rust project." }

Show-Step 3 'Building the controller bridge' 'This can take a few minutes the first time.'
$Manifest = Join-Path $SourceRoot 'rust-bridge\Cargo.toml'
$PreviousCargoPaths = Enable-PrivateCargoPaths
$PreviousErrorActionPreference = $ErrorActionPreference
try {
  $ErrorActionPreference = 'Continue'
  & cargo build --locked --release --manifest-path $Manifest *> $BuildLog
  $CargoExitCode = $LASTEXITCODE
} finally {
  $ErrorActionPreference = $PreviousErrorActionPreference
  Restore-CargoPaths -Previous $PreviousCargoPaths
}
if ($CargoExitCode -ne 0) { throw 'Rust source build failed. Your existing installation was not changed.' }
$Bridge = Join-Path $SourceRoot 'rust-bridge\target\release\rcn-bridge.exe'
if (-not (Test-Path -LiteralPath $Bridge -PathType Leaf)) { throw 'Rust completed without producing rcn-bridge.exe. Your existing installation was not changed.' }
Assert-PrivateArtifact -Path $Bridge
$BridgeHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Bridge).Hash
Write-SourceUi '         Build complete. Checking the finished bridge.' 'Green'

& (Join-Path $SourceRoot 'install-app.ps1') -SourceRoot $SourceRoot -BridgeSource $Bridge -InstallMode "source-build:$Ref" -SourceBuild -InstallerUiStarted
