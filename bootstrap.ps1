[CmdletBinding()]
param([switch]$Repair)
$ErrorActionPreference = 'Stop'
$ReleaseUrl = 'https://github.com/Zouzitou/rcn-fpvskydive/releases/download/v0.1.22/rcn-fpvskydive-v0.1.22.zip'
$ExpectedSha256 = '56172E1E792FA5F6C416B9FC3158EC3DF6BB15FC9BE8536F78DD950EC55539D8'
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
Write-Host "RCN FPV SkyDive installer: preparing per-user environment at $Root"
Copy-Item -Force (Join-Path $SourceRoot 'bin\rcn-bridge.exe') $Bridge
Copy-Item -Force (Join-Path $SourceRoot 'startup.ps1') (Join-Path $Root 'startup.ps1')
Copy-Item -Force (Join-Path $SourceRoot 'uninstall.ps1') (Join-Path $Root 'uninstall.ps1')
Copy-Item -Force (Join-Path $SourceRoot 'launch-fpv.ps1') (Join-Path $Root 'launch-fpv.ps1')
Copy-Item -Force (Join-Path $SourceRoot 'launch-fpv.cmd') (Join-Path $Root 'launch-fpv.cmd')
if (-not (Test-Path -LiteralPath $Bridge)) { throw 'Verified release payload did not contain rcn-bridge.exe.' }
$SelfTest = & $Bridge self-test 2>&1
$SelfTestPassed = $LASTEXITCODE -eq 0
@{ state='installed'; runtime='native-rust'; gamepad_self_test=$SelfTestPassed; self_test_output=($SelfTest -join "`n"); timestamp=(Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json | Set-Content (Join-Path $Root 'state\health.json')
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'startup.ps1') -Action install
if (-not $SelfTestPassed) { Write-Warning 'Native virtual-controller self-test failed. Check the ViGEmBus installation before controller use.' }
Write-Host 'Native environment prepared. Configure the Steam launch option before playing; the bridge does not run at Windows login.'
