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
  $StatusPath = Join-Path $Root 'state\bridge.json'
  $ready = $false
  $deadline = (Get-Date).AddSeconds(15)
  while ((Get-Date) -lt $deadline) {
    if ($BridgeProcess.HasExited) { throw 'The bridge watcher exited before creating the virtual Xbox controller.' }
    if (Test-Path -LiteralPath $StatusPath) {
      try {
        $status = Get-Content -Raw -LiteralPath $StatusPath | ConvertFrom-Json
      } catch [System.Management.Automation.RuntimeException] {
        $status = $null
      } catch {
        # The watcher may be replacing the status file; retry until the deadline.
      }
      if ($status -and $status.state -eq 'connected') { $ready = $true; break }
      if ($status -and $status.state -eq 'awaiting_live_verification') {
        throw 'The controller still needs live-input verification before FPV SkyDive can start.'
      }
    }
    Start-Sleep -Milliseconds 100
  }
  if (-not $ready) { throw 'Timed out waiting for the virtual Xbox controller.' }
  if ($GameArgs.Count -gt 0) {
    $GameProcess = Start-Process -FilePath $GameExe -ArgumentList $GameArgs -PassThru
  } else {
    $GameProcess = Start-Process -FilePath $GameExe -PassThru
  }
  Wait-Process -Id $GameProcess.Id
  exit $GameProcess.ExitCode
} finally {
  Stop-Process -Id $BridgeProcess.Id -Force -ErrorAction SilentlyContinue
  @{ state='stopped'; detail='FPV SkyDive exited'; timestamp=(Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json | Set-Content (Join-Path $Root 'state\bridge.json')
}
