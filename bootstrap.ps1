[CmdletBinding()]
param([switch]$Repair)
$ErrorActionPreference = 'Stop'
$ReleaseUrl = 'https://github.com/Zouzitou/rcn-fpvskydive/releases/download/v0.1.44/rcn-fpvskydive-v0.1.44.zip'
$ExpectedSha256 = 'A5CBBE449F16EF7354F41F8EBFE70C926EAC1EC9C9BC3B4A6963A837B3747F97'
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
$Bin = Join-Path $Root 'bin'
$Bridge = Join-Path $Bin 'rcn-bridge.exe'
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
Write-Host "RCN FPV SkyDive installer: preparing per-user environment at $Root"
Copy-Item -Force (Join-Path $SourceRoot 'bin\rcn-bridge.exe') $Bridge
Copy-Item -Force (Join-Path $SourceRoot 'startup.ps1') (Join-Path $Root 'startup.ps1')
Copy-Item -Force (Join-Path $SourceRoot 'uninstall.ps1') (Join-Path $Root 'uninstall.ps1')
Copy-Item -Force (Join-Path $SourceRoot 'driver.ps1') (Join-Path $Root 'driver.ps1')
Copy-Item -Force (Join-Path $SourceRoot 'open-fpv.ps1') (Join-Path $Root 'open-fpv.ps1')
Copy-Item -Force (Join-Path $SourceRoot 'game-check.ps1') (Join-Path $Root 'game-check.ps1')
Copy-Item -Force (Join-Path $SourceRoot 'launch-fpv.ps1') (Join-Path $Root 'launch-fpv.ps1')
Copy-Item -Force (Join-Path $SourceRoot 'launch-fpv.cmd') (Join-Path $Root 'launch-fpv.cmd')
Copy-Item -Force (Join-Path $SourceRoot 'verify-installed.ps1') (Join-Path $Root 'verify-installed.ps1')
if (-not (Test-Path -LiteralPath $Bridge)) { throw 'Verified release payload did not contain rcn-bridge.exe.' }
$SelfTest = @()
$SelfTestPassed = $false
for ($attempt = 1; $attempt -le 5; $attempt++) {
  $SelfTest = & $Bridge self-test 2>&1
  if ($LASTEXITCODE -eq 0) { $SelfTestPassed = $true; break }
  if ($attempt -lt 5) { Start-Sleep -Seconds 1 }
}
@{ state='installed'; runtime='native-rust'; gamepad_self_test=$SelfTestPassed; self_test_output=($SelfTest -join "`n"); timestamp=(Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json | Set-Content (Join-Path $Root 'state\health.json')
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
} catch {
  Write-Warning "Could not create the optional Start-menu launcher: $($_.Exception.Message)"
}
if (-not $SelfTestPassed) { Write-Warning 'Native virtual-controller self-test failed. Check the ViGEmBus installation before controller use.' }
Write-Host 'Native environment prepared. Use Start Menu > RCN FPV SkyDive for one-click launching; the bridge does not run at Windows login.'
