[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$SourceRoot,
  [Parameter(Mandatory = $true)][string]$BridgeSource,
  [Parameter(Mandatory = $true)][string]$InstallMode,
  [switch]$SourceBuild,
  [switch]$InstallerUiStarted
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'installer-ui.ps1')
$Root = Join-Path $env:LOCALAPPDATA 'RCN-FPVSkyDive'
$Bin = Join-Path $Root 'bin'
$Bridge = Join-Path $Bin 'rcn-bridge.exe'
if (-not (Test-Path -LiteralPath $BridgeSource -PathType Leaf)) { throw 'The native bridge executable was not found in the installer package.' }

if (-not $InstallerUiStarted) {
  Start-InstallerUi 'Getting FPV SkyDive ready'
}
if (-not $SourceBuild) { Set-InstallerStep 1 'Preparing setup' 'Keeping your current controller settings.' }
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

if ($SourceBuild) { Set-InstallerStep 4 'Finishing game setup' 'Installing the bridge and preparing Steam Play.' }
else { Set-InstallerStep 2 'Installing the controller bridge' 'This takes a moment.' }
Copy-Item -LiteralPath $BridgeSource -Destination $Bridge -Force
foreach ($file in 'bootstrap.ps1', 'install-app.ps1', 'startup.ps1', 'uninstall.ps1', 'driver.ps1', 'open-fpv.ps1', 'game-check.ps1', 'launch-fpv.ps1', 'launch-fpv.cmd', 'steam-launch-options.ps1', 'verify-installed.ps1', 'installer-ui.ps1') {
  Copy-Item -LiteralPath (Join-Path $SourceRoot $file) -Destination (Join-Path $Root $file) -Force
}
if (-not (Test-Path -LiteralPath $Bridge)) { throw 'Installation did not produce rcn-bridge.exe.' }

$SelfTest = @()
$SelfTestPassed = $false
if (-not $SourceBuild) { Set-InstallerStep 3 'Preparing game and virtual Xbox' 'Checking the virtual controller and Steam Play setup.' }
for ($attempt = 1; $attempt -le 10; $attempt++) {
  $PreviousErrorActionPreference = $ErrorActionPreference
  try {
    # ViGEm can report TargetNotReady briefly while its neutral test target is
    # becoming available. Capture that native stderr and use the exit code so
    # the retry loop can handle it instead of PowerShell stopping immediately.
    $ErrorActionPreference = 'Continue'
    $SelfTest = & $Bridge self-test 2>&1
    $SelfTestExit = $LASTEXITCODE
  } finally { $ErrorActionPreference = $PreviousErrorActionPreference }
  if ($SelfTestExit -eq 0) { $SelfTestPassed = $true; break }
  if ($attempt -lt 10) { Start-Sleep -Seconds 1 }
}
@{ state = 'installed'; runtime = 'native-rust'; install_mode = $InstallMode; gamepad_self_test = $SelfTestPassed; self_test_output = ($SelfTest -join "`n"); timestamp = (Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json | Set-Content (Join-Path $Root 'state\health.json')
$SteamSetupOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'steam-launch-options.ps1') -Action install 2>&1
$SteamSetupExit = $LASTEXITCODE
$SteamSetup = $null
try { $SteamSetup = ($SteamSetupOutput | Out-String | ConvertFrom-Json) } catch { }
if ($SteamSetupExit -eq 0 -and $SteamSetup.pending) { Write-InstallerText -Text '     Steam is open. Your game is covered for this session; the saved setting will finish after Steam closes.' -Tone 'Amber' }
elseif ($SteamSetupExit -eq 0) { Write-InstallerText -Text '     Steam Play is ready for FPV SkyDive.' -Tone 'Green' }
else { Write-InstallerText -Text '     Steam setup needs another try after Steam is closed.' -Tone 'Amber' }
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
if (-not $SelfTestPassed) {
  Fail-InstallerUi 'The virtual Xbox test did not become ready. The bridge was not marked ready; rerun the installer after checking ViGEmBus.'
  throw 'Virtual Xbox self-test did not pass; installation was not marked ready.'
}
Set-InstallerStep 4 'Checking your controller' 'Looking for an RC-N Protocol connection.'
$DiagnosticPath = Join-Path $Root 'state\installer-diagnose.txt'
$Diagnostic = & $Bridge diagnose --redact 2>&1
$DiagnosticExit = $LASTEXITCODE
$Diagnostic | Set-Content -LiteralPath $DiagnosticPath
$PortMatch = [regex]::Match(($Diagnostic -join "`n"), '(?m)^protocol port: (COM\d+)$')
if ($DiagnosticExit -eq 0 -and $PortMatch.Success) {
  $Port = $PortMatch.Groups[1].Value
  Write-InstallerText -Text ("     Controller found on {0}." -f $Port) -Tone 'Green'
  Write-InstallerTip 'Move each stick when prompted. Press Enter after each movement.'
  $StickChoice = Read-Host 'Press Enter to check your sticks, or type S then Enter to skip for now'
  if ($StickChoice -notmatch '^[sS]$') {
    & $Bridge verify-input --port $Port
    if ($LASTEXITCODE -eq 0) { Write-InstallerText -Text '     All four stick directions are responding.' -Tone 'Green' }
    else { Write-InstallerText -Text '     Stick check was not complete yet. You can retry it from the Flight Console.' -Tone 'Amber' }
  } else { Write-InstallerText -Text '     Stick check skipped. You can run it from the Flight Console whenever you are ready.' -Tone 'Amber' }
} else {
  $Category = [regex]::Match(($Diagnostic -join "`n"), '(?m)^failure category: (.+)$').Groups[1].Value
  Write-InstallerText -Text '     No ready controller connection found yet.' -Tone 'Amber'
  switch ($Category) {
    'controller_not_detected_check_power_data_cable_and_usb_port' { Write-InstallerTip 'Power on the controller, use a USB-C data cable, then reconnect it.' }
    'debug_only_close_assistant_and_reconnect' { Write-InstallerTip 'Close DJI Assistant, reconnect the controller, then run the Flight Console check.' }
    'protocol_interface_present_without_live_frames' { Write-InstallerTip 'The controller was found. Make sure it is powered on, then check the sticks from the Flight Console.' }
    default { Write-InstallerTip 'Connect and power on the controller, then run the Flight Console check.' }
  }
}
Set-InstallerStep 5 'Finishing setup' 'Saving your controller check and game setup.'
if ($SteamSetupExit -eq 0 -and $SteamSetup.pending) { Complete-InstallerUi 'Setup is saved. Close Steam once to finish its saved game setting.' }
elseif ($SteamSetupExit -eq 0) { Complete-InstallerUi 'Setup is complete. Open FPV SkyDive from Steam.' }
else { Complete-InstallerUi 'Setup is complete. Steam setup can be retried from the Flight Console.' }
