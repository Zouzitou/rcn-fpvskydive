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
  # Do not gate the game launch on controller presence. The watcher is
  # deliberately long-lived and can discover a controller that is powered on
  # after FPV SkyDive starts. Until live input is verified it exposes no
  # virtual target and therefore remains neutral/safe.
  Start-Sleep -Milliseconds 250
  if ($BridgeProcess.HasExited) { throw 'The bridge watcher exited before FPV SkyDive could start.' }
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
  $lastGameSeen = $null
  $handoffDeadline = (Get-Date).AddSeconds(15)
  while ($true) {
    $matchingGames = @(Get-Process -Name $gameName -ErrorAction SilentlyContinue | Where-Object {
      try { $_.Path -and ([IO.Path]::GetFullPath($_.Path) -ieq $gamePath) } catch { $false }
    })
    if ($matchingGames.Count -gt 0) {
      $gameSeen = $true
      $lastGameSeen = Get-Date
    }
    # The Steam bootstrap process and the game process are separated by a
    # brief no-process gap. Only stop the bridge after FPV has been absent
    # long enough that this cannot be the normal handoff.
    if ($gameSeen -and $matchingGames.Count -eq 0 -and ((Get-Date) - $lastGameSeen).TotalSeconds -ge 5) { break }
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
