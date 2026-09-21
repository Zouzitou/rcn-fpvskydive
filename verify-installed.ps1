[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$Root = Join-Path $env:LOCALAPPDATA 'RCN-FPVSkyDive'
$Bridge = Join-Path $Root 'bin\rcn-bridge.exe'
$Wrapper = Join-Path $Root 'launch-fpv.ps1'
$Bootstrap = Join-Path $Root 'bootstrap.ps1'
$Installer = Join-Path $Root 'install-app.ps1'
$Shortcut = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\RCN FPV SkyDive.lnk'
if (-not (Test-Path -LiteralPath $Bridge)) { throw "Installed bridge is missing: $Bridge" }
if (-not (Test-Path -LiteralPath $Wrapper)) { throw "Installed wrapper is missing: $Wrapper" }
if (-not (Test-Path -LiteralPath $Bootstrap)) { throw "Installed repair bootstrap is missing: $Bootstrap" }
if (-not (Test-Path -LiteralPath $Installer)) { throw "Installed repair installer is missing: $Installer" }
if (-not (Test-Path -LiteralPath $Shortcut)) { throw "Installed Start-menu launcher is missing: $Shortcut" }
$SteamOptions = Join-Path $Root 'steam-launch-options.ps1'
if (-not (Test-Path -LiteralPath $SteamOptions)) { throw "Installed Steam Play setup helper is missing: $SteamOptions" }

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
$steamStatus = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $SteamOptions -Action status 2>$null | ConvertFrom-Json

# Keep this harmless command alive long enough for the wrapper to observe its
# process and exercise the normal post-game bridge cleanup path. A uniquely
# named temporary copy prevents unrelated cmd.exe sessions from being mistaken
# for the test game by the wrapper's deliberately strict path/name matching.
$TestExe = Join-Path $env:TEMP ('rcn-wrapper-test-' + [guid]::NewGuid().ToString('N') + '.exe')
Copy-Item -LiteralPath $env:ComSpec -Destination $TestExe -Force
try {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Wrapper $TestExe /d /c 'ping -n 3 127.0.0.1 > nul'
  if ($LASTEXITCODE -ne 0) { throw "Wrapper lifecycle failed with exit code $LASTEXITCODE." }
} finally {
  Remove-Item -LiteralPath $TestExe -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Milliseconds 500
$watchers = @(Get-CimInstance Win32_Process -Filter "Name = 'rcn-bridge.exe'" | Where-Object {
  $_.ExecutablePath -eq $Bridge -and $_.CommandLine -like '* watch*'
})
if ($watchers.Count -ne 0) { throw "Wrapper left $($watchers.Count) bridge watcher process(es)." }

[pscustomobject]@{
  installed = $true
  self_test = 'passed'
  startup_mode = $startup.method
  start_menu_launcher = $true
  repair_payload = $true
  steam_play_configured = [bool]$steamStatus.configured
  steam_play_pending = [bool]$steamStatus.pending
  wrapper_exit = 0
  remaining_watchers = $watchers.Count
} | ConvertTo-Json
