[CmdletBinding(SupportsShouldProcess)]
param()
$Root = Join-Path $env:LOCALAPPDATA 'RCN-FPVSkyDive'
$Shortcut = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\RCN FPV SkyDive.lnk'
if (Test-Path $Root) {
  $Startup = Join-Path $Root 'startup.ps1'
  if (Test-Path $Startup) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Startup -Action remove }
  $SteamLaunchOptions = Join-Path $Root 'steam-launch-options.ps1'
  if (Test-Path $SteamLaunchOptions) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $SteamLaunchOptions -Action remove }
  if ($PSCmdlet.ShouldProcess($Root, 'remove RCN FPV SkyDive application data')) { Remove-Item -LiteralPath $Root -Recurse -Force }
}
Remove-Item -LiteralPath $Shortcut -Force -ErrorAction SilentlyContinue
Write-Host 'RCN FPV SkyDive user files removed. Driver-store packages, if installed, require the repair/uninstall driver flow.'
