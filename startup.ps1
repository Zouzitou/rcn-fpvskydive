[CmdletBinding()]
param(
  [ValidateSet('install','remove')][string]$Action = 'install',
  [string]$TaskName = 'RCN-FPVSkyDive Bridge'
)
$ErrorActionPreference = 'Stop'
$Root = Join-Path $env:LOCALAPPDATA 'RCN-FPVSkyDive'
$Bridge = Join-Path $Root 'bin\rcn-bridge.exe'
$Run = "`"$Bridge`" watch"
$Health = Join-Path $Root 'state\startup.json'
New-Item -ItemType Directory -Force (Split-Path $Health) | Out-Null
function Get-BridgeProcesses {
  @(Get-CimInstance Win32_Process -Filter "Name = 'rcn-bridge.exe'" -ErrorAction Stop | Where-Object {
    $_.ExecutablePath -eq $Bridge -and $_.CommandLine -like '* watch*'
  })
}
function Test-BridgeLaunch {
  try {
    $processes = @(Get-BridgeProcesses)
    if ($processes.Count -eq 0) {
      Start-Process -FilePath $Bridge -ArgumentList @('watch') -WindowStyle Hidden
      Start-Sleep -Seconds 2
      $processes = @(Get-BridgeProcesses)
    }
    return @{ attempted=$true; passed=($processes.Count -eq 1); bridge_pids=@($processes | ForEach-Object { $_.ProcessId }) }
  } catch {
    return @{ attempted=$true; passed=$false; error=$_.Exception.Message; bridge_pids=@() }
  }
}
if ($Action -eq 'remove') {
  @(Get-BridgeProcesses) | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  schtasks.exe /Delete /TN $TaskName /F 2>$null | Out-Null
  Remove-Item -LiteralPath (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\RCN-FPVSkyDive.cmd') -Force -ErrorAction SilentlyContinue
  @{ method='none'; removed=$true; timestamp=(Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json | Set-Content $Health
  exit 0
}
if (-not (Test-Path -LiteralPath $Bridge)) { throw "Native bridge executable is missing: $Bridge" }
$task = @()
$taskExit = 1
try {
  $task = @(schtasks.exe /Create /SC ONLOGON /TN $TaskName /TR $Run /F /RL LIMITED 2>&1)
  $taskExit = $LASTEXITCODE
} catch {
  $task = @($_.Exception.Message)
}
if ($taskExit -eq 0) {
  try { schtasks.exe /Run /TN $TaskName 2>$null | Out-Null } catch { }
  $launch = Test-BridgeLaunch
  @{ method='scheduled-task'; command=$Run; startup_test=$launch; timestamp=(Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json | Set-Content $Health
  if ($launch.passed) { Write-Host 'Startup registered with a per-user scheduled task and immediate launch test passed.' }
  else { Write-Warning 'Startup task was registered, but its immediate launch test did not find exactly one bridge watchdog.' }
  exit 0
}
$startup = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\RCN-FPVSkyDive.cmd'
Set-Content -LiteralPath $startup -Value "@echo off`r`n$Run`r`n"
$launch = Test-BridgeLaunch
@{ method='startup-folder'; command=$Run; task_error=($task -join ' '); startup_test=$launch; timestamp=(Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json | Set-Content $Health
if ($launch.passed) { Write-Host 'Scheduled task was unavailable; Startup fallback registered and immediate launch test passed.' }
else { Write-Warning 'Startup fallback was registered, but its immediate launch test did not find exactly one bridge watchdog.' }
