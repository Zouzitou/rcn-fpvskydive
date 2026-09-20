[CmdletBinding()]
param([ValidateSet('install','remove')][string]$Action = 'install')
$ErrorActionPreference = 'Stop'
$Root = Join-Path $env:LOCALAPPDATA 'RCN-FPVSkyDive'
$Py = Join-Path $Root '.venv\Scripts\python.exe'
$TaskName = 'RCN-FPVSkyDive Bridge'
$Run = "`"$Py`" -m rcn_fpv.watchdog"
$Health = Join-Path $Root 'state\startup.json'
New-Item -ItemType Directory -Force (Split-Path $Health) | Out-Null
if ($Action -eq 'remove') {
  schtasks.exe /Delete /TN $TaskName /F 2>$null | Out-Null
  Remove-Item -LiteralPath (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\RCN-FPVSkyDive.cmd') -Force -ErrorAction SilentlyContinue
  @{ method='none'; removed=$true; timestamp=(Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json | Set-Content $Health
  exit 0
}
$task = schtasks.exe /Create /SC ONLOGON /TN $TaskName /TR $Run /F /RL LIMITED 2>&1
if ($LASTEXITCODE -eq 0) {
  schtasks.exe /Run /TN $TaskName | Out-Null
  Start-Sleep -Seconds 2
  @{ method='scheduled-task'; command=$Run; timestamp=(Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json | Set-Content $Health
  Write-Host 'Startup registered with a per-user scheduled task.'
  exit 0
}
$startup = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\RCN-FPVSkyDive.cmd'
Set-Content -LiteralPath $startup -Value "@echo off`r`n$Run`r`n"
@{ method='startup-folder'; command=$Run; task_error=($task -join ' '); timestamp=(Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json | Set-Content $Health
Write-Host 'Scheduled task was unavailable; registered current-user Startup fallback.'
