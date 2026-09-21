[CmdletBinding(SupportsShouldProcess)]
param()
$Root = Join-Path $env:LOCALAPPDATA 'RCN-FPVSkyDive'
if (Test-Path $Root) {
  $Startup = Join-Path $Root 'startup.ps1'
  if (Test-Path $Startup) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Startup -Action remove }
  if ($PSCmdlet.ShouldProcess($Root, 'remove RCN FPV SkyDive application data')) { Remove-Item -LiteralPath $Root -Recurse -Force }
}
Write-Host 'RCN FPV SkyDive user files removed. Driver-store packages, if installed, require the repair/uninstall driver flow.'
