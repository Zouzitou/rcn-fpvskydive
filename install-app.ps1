[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$SourceRoot,
  [Parameter(Mandatory = $true)][string]$BridgeSource,
  [Parameter(Mandatory = $true)][string]$InstallMode
)

$ErrorActionPreference = 'Stop'
$Root = Join-Path $env:LOCALAPPDATA 'RCN-FPVSkyDive'
$Bin = Join-Path $Root 'bin'
$Bridge = Join-Path $Bin 'rcn-bridge.exe'
if (-not (Test-Path -LiteralPath $BridgeSource -PathType Leaf)) { throw "The native bridge executable was not found: $BridgeSource" }

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

Write-Host "Installing $InstallMode build into $Root"
Copy-Item -LiteralPath $BridgeSource -Destination $Bridge -Force
foreach ($file in 'startup.ps1', 'uninstall.ps1', 'driver.ps1', 'open-fpv.ps1', 'game-check.ps1', 'launch-fpv.ps1', 'launch-fpv.cmd', 'verify-installed.ps1') {
  Copy-Item -LiteralPath (Join-Path $SourceRoot $file) -Destination (Join-Path $Root $file) -Force
}
if (-not (Test-Path -LiteralPath $Bridge)) { throw 'Installation did not produce rcn-bridge.exe.' }

$SelfTest = @()
$SelfTestPassed = $false
for ($attempt = 1; $attempt -le 5; $attempt++) {
  $SelfTest = & $Bridge self-test 2>&1
  if ($LASTEXITCODE -eq 0) { $SelfTestPassed = $true; break }
  if ($attempt -lt 5) { Start-Sleep -Seconds 1 }
}
@{ state = 'installed'; runtime = 'native-rust'; install_mode = $InstallMode; gamepad_self_test = $SelfTestPassed; self_test_output = ($SelfTest -join "`n"); timestamp = (Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json | Set-Content (Join-Path $Root 'state\health.json')
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'startup.ps1') -Action install

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
} catch { Write-Warning "Could not create the optional Start-menu launcher: $($_.Exception.Message)" }
if (-not $SelfTestPassed) { Write-Warning 'Native virtual-controller self-test failed. Check the ViGEmBus installation before controller use.' }
Write-Host 'Installation finished. Use Start Menu > RCN FPV SkyDive to launch; the bridge never runs at Windows login.'
