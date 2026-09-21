[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$SourceRoot,
  [Parameter(Mandatory = $true)][string]$BridgeSource,
  [Parameter(Mandatory = $true)][string]$InstallMode,
  [switch]$SourceBuild
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'installer-ui.ps1')
$Root = Join-Path $env:LOCALAPPDATA 'RCN-FPVSkyDive'
$Bin = Join-Path $Root 'bin'
$Bridge = Join-Path $Bin 'rcn-bridge.exe'
if (-not (Test-Path -LiteralPath $BridgeSource -PathType Leaf)) { throw 'The native bridge executable was not found in the installer package.' }

if (-not $SourceBuild) {
  Start-InstallerUi 'Private, per-user installer  •  no driver changes'
  Set-InstallerStep 1 'Preparing a private application space' 'Keeping your existing mapping and settings.'
}
New-Item -ItemType Directory -Force -Path $Bin,(Join-Path $Root 'drivers'),(Join-Path $Root 'logs'),(Join-Path $Root 'state') | Out-Null
$MappingConfig = Join-Path $Root 'state\mapping.conf'
if (-not (Test-Path -LiteralPath $MappingConfig)) {
  @'
# Native Mode 2 defaults. Values are clamped by the bridge.
# Axis fields: invert=true|false, deadzone=0..0.95, trim=-1..1,
# saturation=0.05..1, curve=0.1..4.
left_x.invert=false
left_x.deadzone=0
left_x.trim=0
left_x.saturation=1
left_x.curve=1
left_y.invert=false
left_y.deadzone=0
left_y.trim=0
left_y.saturation=1
left_y.curve=1
right_x.invert=false
right_x.deadzone=0
right_x.trim=0
right_x.saturation=1
right_x.curve=1
right_y.invert=false
right_y.deadzone=0
right_y.trim=0
right_y.saturation=1
right_y.curve=1
'@ | Set-Content -LiteralPath $MappingConfig -NoNewline
}

if ($SourceBuild) { Set-InstallerStep 4 'Installing the locally built bridge' 'Keeping your existing mapping and settings.' }
else { Set-InstallerStep 2 'Installing the native controller bridge' 'No Python runtime is required.' }
Copy-Item -LiteralPath $BridgeSource -Destination $Bridge -Force
foreach ($file in 'bootstrap.ps1', 'install-app.ps1', 'startup.ps1', 'uninstall.ps1', 'driver.ps1', 'open-fpv.ps1', 'game-check.ps1', 'launch-fpv.ps1', 'launch-fpv.cmd', 'steam-launch-options.ps1', 'verify-installed.ps1', 'installer-ui.ps1') {
  Copy-Item -LiteralPath (Join-Path $SourceRoot $file) -Destination (Join-Path $Root $file) -Force
}
if (-not (Test-Path -LiteralPath $Bridge)) { throw 'Installation did not produce rcn-bridge.exe.' }

$SelfTest = @()
$SelfTestPassed = $false
if ($SourceBuild) { Set-InstallerStep 5 'Checking the virtual Xbox controller' 'A neutral, temporary controller test is running.' }
else { Set-InstallerStep 3 'Checking the virtual Xbox controller' 'A neutral, temporary controller test is running.' }
for ($attempt = 1; $attempt -le 5; $attempt++) {
  $SelfTest = & $Bridge self-test 2>&1
  if ($LASTEXITCODE -eq 0) { $SelfTestPassed = $true; break }
  if ($attempt -lt 5) { Start-Sleep -Seconds 1 }
}
@{ state = 'installed'; runtime = 'native-rust'; install_mode = $InstallMode; gamepad_self_test = $SelfTestPassed; self_test_output = ($SelfTest -join "`n"); timestamp = (Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json | Set-Content (Join-Path $Root 'state\health.json')
if (-not $SourceBuild) { Set-InstallerStep 4 'Setting up Steam Play' 'Your normal Steam Play button will start the bridge.' }
$SteamSetupOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'steam-launch-options.ps1') -Action install 2>&1
$SteamSetupExit = $LASTEXITCODE
$SteamSetup = $null
try { $SteamSetup = ($SteamSetupOutput | Out-String | ConvertFrom-Json) } catch { }
if ($SteamSetupExit -eq 0 -and $SteamSetup.pending) { Write-InstallerText '     Steam is open; Play setup will finish automatically when Steam closes.' 'Amber' }
elseif ($SteamSetupExit -eq 0) { Write-InstallerText '     Steam Play is configured for FPV SkyDive.' 'Green' }
else { Write-InstallerText '     Steam Play setup could not finish. Run the installer again when Steam is closed.' 'Amber' }
$StartupOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'startup.ps1') -Action install 2>&1
if ($LASTEXITCODE -ne 0) { throw 'Could not configure the game-only launcher.' }

$StartMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
$Shortcut = Join-Path $StartMenu 'RCN FPV SkyDive.lnk'
try {
  New-Item -ItemType Directory -Force -Path $StartMenu | Out-Null
  $Shell = New-Object -ComObject WScript.Shell
  $Link = $Shell.CreateShortcut($Shortcut)
  $Link.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
  $Link.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $Root 'open-fpv.ps1')`""
  $Link.WorkingDirectory = $Root
  $Link.Description = 'Start FPV SkyDive with the RCN virtual Xbox controller'
  $Link.Save()
} catch { Write-InstallerText '     Start Menu shortcut was unavailable; the Steam launch option still works.' 'Amber' }
if (-not $SourceBuild) { Set-InstallerStep 5 'Finishing safely' 'No controller driver was installed or changed.' }
if (-not $SelfTestPassed) { Write-InstallerText '     Virtual Xbox self-test needs attention. Check ViGEmBus before flying.' 'Amber' }
if ($SteamSetupExit -eq 0 -and $SteamSetup.pending) { Complete-InstallerUi 'Steam Play will be ready automatically after Steam closes once.' }
elseif ($SteamSetupExit -eq 0) { Complete-InstallerUi 'Open FPV SkyDive with the normal Steam Play button.' }
else { Complete-InstallerUi 'Start Menu works now; Steam Play can be repaired by rerunning this installer.' }
