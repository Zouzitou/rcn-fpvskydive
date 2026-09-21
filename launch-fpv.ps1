[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$GameCommand)
$ErrorActionPreference = 'Stop'
$Root = Join-Path $env:LOCALAPPDATA 'RCN-FPVSkyDive'
$Bridge = Join-Path $Root 'bin\rcn-bridge.exe'
if (-not (Test-Path -LiteralPath $Bridge)) { throw "Native bridge executable is missing: $Bridge" }
if (-not $GameCommand -or $GameCommand.Count -eq 0) { throw 'This launcher must be called by Steam with %command%.' }
$GameExe = $GameCommand[0]
$GameArgs = @($GameCommand | Select-Object -Skip 1)
$BridgeProcess = Start-Process -FilePath $Bridge -ArgumentList @('watch') -WindowStyle Hidden -PassThru
try {
  $GameProcess = Start-Process -FilePath $GameExe -ArgumentList $GameArgs -PassThru
  Wait-Process -Id $GameProcess.Id
  exit $GameProcess.ExitCode
} finally {
  Stop-Process -Id $BridgeProcess.Id -Force -ErrorAction SilentlyContinue
}
