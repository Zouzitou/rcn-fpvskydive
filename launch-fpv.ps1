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
  # FPV SkyDive can hand off from Steam's initial process to a separate game
  # process. Keep the virtual controller alive for that child, not just the
  # short-lived process Start-Process first returns.
  $gameName = [IO.Path]::GetFileNameWithoutExtension($GameExe)
  $gamePath = [IO.Path]::GetFullPath($GameExe)
  $gameSeen = $false
  $handoffDeadline = (Get-Date).AddSeconds(15)
  while ($true) {
    $matchingGames = @(Get-Process -Name $gameName -ErrorAction SilentlyContinue | Where-Object {
      try { $_.Path -and ([IO.Path]::GetFullPath($_.Path) -ieq $gamePath) } catch { $false }
    })
    if ($matchingGames.Count -gt 0) { $gameSeen = $true }
    if ($gameSeen -and $matchingGames.Count -eq 0) { break }
    if (-not $gameSeen -and $GameProcess.HasExited -and (Get-Date) -ge $handoffDeadline) {
      throw 'FPV SkyDive exited before its game process became available.'
    }
    Start-Sleep -Milliseconds 250
  }
  exit 0
} finally {
  Stop-Process -Id $BridgeProcess.Id -Force -ErrorAction SilentlyContinue
  @{ state='stopped'; detail='FPV SkyDive exited'; timestamp=(Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json | Set-Content (Join-Path $Root 'state\bridge.json')
}
