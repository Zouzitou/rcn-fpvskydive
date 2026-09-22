[CmdletBinding(SupportsShouldProcess)]
param()
$Root = Join-Path $env:LOCALAPPDATA 'RCN-FPVSkyDive'
$Shortcut = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\RCN FPV SkyDive.lnk'
$Steam = Get-Process -Name steam -ErrorAction SilentlyContinue
if ($Steam) {
  $SteamExe = $Steam | Select-Object -First 1 -ExpandProperty Path
  if ($SteamExe -and $PSCmdlet.ShouldProcess('Steam', 'close before restoring FPV SkyDive launch settings')) {
    Start-Process -FilePath $SteamExe -ArgumentList '-shutdown' -WindowStyle Hidden
    $deadline = (Get-Date).AddSeconds(20)
    do {
      Start-Sleep -Milliseconds 250
      $Steam = Get-Process -Name steam -ErrorAction SilentlyContinue
    } while ($Steam -and (Get-Date) -lt $deadline)
  }
}
if (Get-Process -Name steam -ErrorAction SilentlyContinue) { throw 'Steam is still running. Close Steam, then run the uninstaller again; no files were removed.' }
if (Test-Path $Root) {
  $Startup = Join-Path $Root 'startup.ps1'
  if (Test-Path $Startup) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Startup -Action remove }
  $SteamLaunchOptions = Join-Path $Root 'steam-launch-options.ps1'
  if (Test-Path $SteamLaunchOptions) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $SteamLaunchOptions -Action remove }
  else { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'steam-launch-options.ps1') -Action remove }
  if ($PSCmdlet.ShouldProcess($Root, 'remove RCN FPV SkyDive application data')) { Remove-Item -LiteralPath $Root -Recurse -Force }
} else {
  $RecoveryScript = Join-Path $PSScriptRoot 'steam-launch-options.ps1'
  if (Test-Path $RecoveryScript) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $RecoveryScript -Action remove }
}
Remove-Item -LiteralPath $Shortcut -Force -ErrorAction SilentlyContinue
Write-Host 'RCN FPV SkyDive user files removed. Driver-store packages, if installed, require the repair/uninstall driver flow.'
