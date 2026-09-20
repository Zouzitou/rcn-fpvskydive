[CmdletBinding(SupportsShouldProcess)]
param()
$Root = Join-Path $env:LOCALAPPDATA 'RCN-FPVSkyDive'
if (Test-Path $Root) {
  if ($PSCmdlet.ShouldProcess($Root, 'remove RCN FPV SkyDive application data')) { Remove-Item -LiteralPath $Root -Recurse -Force }
}
Write-Host 'RCN FPV SkyDive user files removed. Driver-store packages, if installed, require the repair/uninstall driver flow.'
