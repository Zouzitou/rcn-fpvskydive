[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$Root = Join-Path $env:LOCALAPPDATA 'RCN-FPVSkyDive'
$Bridge = Join-Path $Root 'bin\rcn-bridge.exe'
$Wrapper = Join-Path $Root 'launch-fpv.ps1'
if (-not (Test-Path -LiteralPath $Bridge)) { throw "Installed bridge is missing: $Bridge" }
if (-not (Test-Path -LiteralPath $Wrapper)) { throw "Installed wrapper is missing: $Wrapper" }

$selfTestPassed = $false
for ($attempt = 1; $attempt -le 5; $attempt++) {
  $selfTest = & $Bridge self-test 2>&1
  if ($LASTEXITCODE -eq 0) { $selfTestPassed = $true; break }
  if ($attempt -lt 5) { Start-Sleep -Seconds 1 }
}
if (-not $selfTestPassed) { throw "ViGEm self-test failed: $($selfTest -join ' ')" }

$startupPath = Join-Path $Root 'state\startup.json'
$startup = if (Test-Path -LiteralPath $startupPath) { Get-Content -LiteralPath $startupPath -Raw | ConvertFrom-Json } else { $null }
if (-not $startup -or $startup.method -ne 'steam-launch-wrapper') { throw 'Login startup is not in the expected game-wrapper mode.' }

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Wrapper cmd.exe /d /c exit 0
if ($LASTEXITCODE -ne 0) { throw "Wrapper lifecycle failed with exit code $LASTEXITCODE." }
Start-Sleep -Milliseconds 500
$watchers = @(Get-CimInstance Win32_Process -Filter "Name = 'rcn-bridge.exe'" | Where-Object {
  $_.ExecutablePath -eq $Bridge -and $_.CommandLine -like '* watch*'
})
if ($watchers.Count -ne 0) { throw "Wrapper left $($watchers.Count) bridge watcher process(es)." }

[pscustomobject]@{
  installed = $true
  self_test = 'passed'
  startup_mode = $startup.method
  wrapper_exit = 0
  remaining_watchers = $watchers.Count
} | ConvertTo-Json
