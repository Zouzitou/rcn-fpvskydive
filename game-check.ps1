[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$Root = Join-Path $env:LOCALAPPDATA 'RCN-FPVSkyDive'
$Bridge = Join-Path $Root 'bin\rcn-bridge.exe'
if (-not (Test-Path -LiteralPath $Bridge)) { throw "Installed bridge is missing: $Bridge" }

$game = @(Get-CimInstance Win32_Process -Filter "Name = 'FPV.SkyDive.exe'" | Where-Object {
  $_.ExecutablePath -and $_.ExecutablePath -match '\\FPV\.SkyDive\\FPV\.SkyDive\.exe$'
})
$statusText = & $Bridge status 2>&1
if ($LASTEXITCODE -ne 0) { throw "Could not read bridge status: $($statusText -join ' ')" }
try {
  $bridgeStatus = $statusText | ConvertFrom-Json
} catch {
  throw "Bridge status was not valid JSON: $($statusText -join ' ')"
}
$xbox = @(Get-PnpDevice -PresentOnly | Where-Object {
  $_.Status -eq 'OK' -and ($_.Class -eq 'XnaComposite' -or $_.FriendlyName -match 'Xbox 360.*Windows')
})
$passed = $game.Count -gt 0 -and $bridgeStatus.state -eq 'connected' -and $xbox.Count -gt 0
[pscustomobject]@{
  passed = $passed
  game_processes = @($game | ForEach-Object { @{ pid=$_.ProcessId; path=$_.ExecutablePath } })
  bridge_state = $bridgeStatus.state
  mapped_frames = $bridgeStatus.mapped_frames
  xbox_controllers = @($xbox | ForEach-Object { @{ name=$_.FriendlyName; instance_id=$_.InstanceId } })
} | ConvertTo-Json -Depth 5
if (-not $passed) { exit 2 }
