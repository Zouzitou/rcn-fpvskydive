[CmdletBinding()]
param(
  [ValidateSet('install','remove')][string]$Action = 'install',
  [string]$TaskName = 'RCN-FPVSkyDive Bridge'
)
$ErrorActionPreference = 'Stop'
$Root = Join-Path $env:LOCALAPPDATA 'RCN-FPVSkyDive'
$Bridge = Join-Path $Root 'bin\rcn-bridge.exe'
$Health = Join-Path $Root 'state\startup.json'
New-Item -ItemType Directory -Force (Split-Path $Health) | Out-Null
function Get-BridgeProcesses {
  @(Get-CimInstance Win32_Process -Filter "Name = 'rcn-bridge.exe'" -ErrorAction Stop | Where-Object {
    $_.ExecutablePath -eq $Bridge -and $_.CommandLine -like '* watch*'
  })
}
function Remove-LoginBridge {
  @(Get-BridgeProcesses) | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  $oldErrorActionPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'SilentlyContinue'
    schtasks.exe /Delete /TN $TaskName /F 2>$null | Out-Null
  } finally {
    $ErrorActionPreference = $oldErrorActionPreference
  }
  Remove-Item -LiteralPath (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\RCN-FPVSkyDive.cmd') -Force -ErrorAction SilentlyContinue
}
if ($Action -eq 'remove') {
  Remove-LoginBridge
  @{ method='none'; removed=$true; timestamp=(Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json | Set-Content $Health
  exit 0
}
Remove-LoginBridge
@{ method='steam-launch-wrapper'; command='Steam launch option starts the bridge only for FPV SkyDive'; timestamp=(Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json | Set-Content $Health
Write-Host 'Login startup is disabled. Configure the FPV SkyDive Steam launch option to use launch-fpv.cmd.'
