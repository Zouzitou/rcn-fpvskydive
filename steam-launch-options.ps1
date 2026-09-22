[CmdletBinding()]
param(
  [ValidateSet('install', 'remove', 'status')][string]$Action = 'install',
  [string[]]$ConfigPath,
  [switch]$WaitForSteamExit
)

$ErrorActionPreference = 'Stop'
$AppId = '1278060'
$Root = Join-Path $env:LOCALAPPDATA 'RCN-FPVSkyDive'
$StatePath = Join-Path $Root 'state\steam-launch-options.json'
$PendingPath = Join-Path $Root 'state\steam-launch-options-pending.json'
$WrapperMarker = 'RCN-FPVSkyDive\launch-fpv.cmd'
$WrapperCommand = 'cmd.exe /d /c call "%LOCALAPPDATA%\RCN-FPVSkyDive\launch-fpv.cmd" %command%'

function Get-SteamRoots {
  $roots = [System.Collections.Generic.List[string]]::new()
  foreach ($key in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam') {
    $item = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
    foreach ($value in @($item.SteamPath, $item.InstallPath)) { if ($value) { [void]$roots.Add($value) } }
    if ($item.SteamExe) { [void]$roots.Add((Split-Path $item.SteamExe)) }
  }
  @($roots | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)
}

function Get-ConfigPaths {
  if ($ConfigPath) { return @($ConfigPath | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -Unique) }
  @(Get-SteamRoots | ForEach-Object {
    $userdata = Join-Path $_ 'userdata'
    Get-ChildItem -LiteralPath $userdata -Directory -ErrorAction SilentlyContinue | ForEach-Object {
      $candidate = Join-Path $_.FullName 'config\localconfig.vdf'
      if (Test-Path -LiteralPath $candidate -PathType Leaf) { $candidate }
    }
  } | Select-Object -Unique)
}

function Get-VdfText {
  param([string]$Path)
  $bytes = [IO.File]::ReadAllBytes($Path)
  $encoding = [Text.UTF8Encoding]::new($false)
  if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { $encoding = [Text.Encoding]::Unicode }
  elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) { $encoding = [Text.Encoding]::BigEndianUnicode }
  elseif ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $encoding = [Text.UTF8Encoding]::new($true) }
  [pscustomobject]@{ text = $encoding.GetString($bytes); encoding = $encoding }
}

function Find-MatchingBrace {
  param([string]$Text, [int]$OpenIndex)
  $depth = 0; $quoted = $false; $escaped = $false
  for ($index = $OpenIndex; $index -lt $Text.Length; $index++) {
    $character = $Text[$index]
    if ($quoted) {
      if ($escaped) { $escaped = $false }
      elseif ($character -eq '\') { $escaped = $true }
      elseif ($character -eq '"') { $quoted = $false }
      continue
    }
    if ($character -eq '"') { $quoted = $true; continue }
    if ($character -eq '{') { $depth++ }
    elseif ($character -eq '}') { $depth--; if ($depth -eq 0) { return $index } }
  }
  throw 'Steam configuration has an incomplete VDF block.'
}

function Find-VdfBlock {
  param([string]$Text, [string]$Key, [int]$From = 0, [int]$To = -1)
  if ($To -lt 0) { $To = $Text.Length }
  $match = [regex]::Match($Text.Substring($From, $To - $From), ('(?is)"' + [regex]::Escape($Key) + '"\s*\{'))
  if (-not $match.Success) { return $null }
  $open = $From + $match.Index + $match.Length - 1
  [pscustomobject]@{ open = $open; close = (Find-MatchingBrace -Text $Text -OpenIndex $open) }
}

function Escape-VdfValue { param([string]$Value) $Value.Replace('\', '\\').Replace('"', '\"') }
function Unescape-VdfValue { param([string]$Value) [regex]::Replace($Value, '\\(.)', '$1') }

function Get-LaunchOptions {
  param([string]$Text, [object]$AppBlock)
  $bodyStart = $AppBlock.open + 1
  $body = $Text.Substring($bodyStart, $AppBlock.close - $bodyStart)
  $match = [regex]::Match($body, '(?im)^(?<indent>[\t ]*)"LaunchOptions"\s+"(?<value>(?:\\.|[^"])*)"')
  if (-not $match.Success) { return $null }
  [pscustomobject]@{
    start = $bodyStart + $match.Index
    length = $match.Length
    indent = $match.Groups['indent'].Value
    value = (Unescape-VdfValue $match.Groups['value'].Value)
  }
}

function Set-LaunchOptions {
  param([string]$Text, [string]$Value)
  $newline = if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" }
  $apps = Find-VdfBlock -Text $Text -Key 'apps'
  if ($null -eq $apps) { throw 'Steam configuration has no apps section. Open Steam once, close it, then rerun the installer.' }
  $app = Find-VdfBlock -Text $Text -Key $AppId -From ($apps.open + 1) -To $apps.close
  $encoded = Escape-VdfValue $Value
  if ($null -eq $app) {
    $insert = "$newline`t`t`t`"$AppId`"$newline`t`t`t{$newline`t`t`t`t`"LaunchOptions`" `"$encoded`"$newline`t`t`t}$newline"
    return $Text.Insert($apps.close, $insert)
  }
  $existing = Get-LaunchOptions -Text $Text -AppBlock $app
  if ($null -ne $existing) {
    return $Text.Remove($existing.start, $existing.length).Insert($existing.start, ($existing.indent + '"LaunchOptions" "' + $encoded + '"'))
  }
  $indent = "`t`t`t`t"
  return $Text.Insert($app.open + 1, "$newline$indent`"LaunchOptions`" `"$encoded`"")
}

function Remove-LaunchOptions {
  param([string]$Text, [string]$RestoreValue, [bool]$HadOriginal)
  $apps = Find-VdfBlock -Text $Text -Key 'apps'
  if ($null -eq $apps) { return $Text }
  $app = Find-VdfBlock -Text $Text -Key $AppId -From ($apps.open + 1) -To $apps.close
  if ($null -eq $app) { return $Text }
  $existing = Get-LaunchOptions -Text $Text -AppBlock $app
  if ($null -eq $existing -or $existing.value -notmatch [regex]::Escape($WrapperMarker)) { return $Text }
  if ($HadOriginal) { return Set-LaunchOptions -Text $Text -Value $RestoreValue }
  $lineStart = $existing.start
  $lineLength = $existing.length
  if ($lineStart + $lineLength -lt $Text.Length -and $Text[$lineStart + $lineLength] -eq "`r") { $lineLength++ }
  if ($lineStart + $lineLength -lt $Text.Length -and $Text[$lineStart + $lineLength] -eq "`n") { $lineLength++ }
  return $Text.Remove($lineStart, $lineLength)
}

function Write-VdfText { param([string]$Path, [string]$Text, [object]$Encoding) [IO.File]::WriteAllText($Path, $Text, $Encoding) }

function Start-PendingGameBridge {
  $bridge = Join-Path $Root 'bin\rcn-bridge.exe'
  if (-not (Test-Path -LiteralPath $bridge -PathType Leaf)) { return $null }
  $watcher = @(Get-CimInstance Win32_Process -Filter "Name = 'rcn-bridge.exe'" -ErrorAction SilentlyContinue | Where-Object {
    $_.ExecutablePath -eq $bridge -and $_.CommandLine -like '* watch*'
  } | Select-Object -First 1)
  if ($watcher.Count -gt 0) { return $null }
  (Start-Process -FilePath $bridge -ArgumentList 'watch' -WindowStyle Hidden -PassThru).Id
}

function Stop-PendingGameBridge {
  param([Nullable[int]]$ProcessId)
  if ($null -eq $ProcessId) { return }
  Get-Process -Id $ProcessId -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

if (-not $ConfigPath -and (Get-Process -Name steam -ErrorAction SilentlyContinue)) {
  if ($Action -eq 'status') {
    $pending = Test-Path -LiteralPath $PendingPath
    [pscustomobject]@{ configured = $false; pending = $pending; detail = if ($pending) { 'Steam Play setup will finish after Steam exits; the pending worker starts the bridge for an FPV SkyDive session meanwhile.' } else { 'Steam is running; Steam Play setup is not yet configured.' } } | ConvertTo-Json
    exit 0
  }
  if ($Action -eq 'remove') { throw 'Close Steam completely, then run uninstall again so the original Steam launch option can be restored safely.' }
  if (-not $WaitForSteamExit) {
    New-Item -ItemType Directory -Force -Path (Split-Path $PendingPath) | Out-Null
    $pending = if (Test-Path -LiteralPath $PendingPath) { Get-Content -LiteralPath $PendingPath -Raw | ConvertFrom-Json } else { $null }
    $workerAlive = $pending -and $pending.pid -and (Get-Process -Id $pending.pid -ErrorAction SilentlyContinue)
    if (-not $workerAlive) {
      $worker = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-Action', 'install', '-WaitForSteamExit') -WindowStyle Hidden -PassThru
      @{ pid = $worker.Id; state = 'waiting_for_steam_exit'; timestamp = (Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath $PendingPath
    }
    [pscustomobject]@{ configured = $false; pending = $true; detail = 'Steam Play setup will finish automatically after Steam exits; the worker also covers an FPV SkyDive session in the meantime.' } | ConvertTo-Json
    exit 0
  }
  $ownedBridgePid = $null
  $lastGameSeen = [DateTime]::MinValue
  try {
    while (Get-Process -Name steam -ErrorAction SilentlyContinue) {
      if (Get-Process -Name 'FPV.SkyDive' -ErrorAction SilentlyContinue) {
        $lastGameSeen = Get-Date
        if ($null -eq $ownedBridgePid) { $ownedBridgePid = Start-PendingGameBridge }
      } elseif ($null -ne $ownedBridgePid -and ((Get-Date) - $lastGameSeen).TotalSeconds -ge 5) {
        Stop-PendingGameBridge -ProcessId $ownedBridgePid
        $ownedBridgePid = $null
      }
      Start-Sleep -Seconds 2
    }
  } finally {
    Stop-PendingGameBridge -ProcessId $ownedBridgePid
  }
}

$configs = @(Get-ConfigPaths)
if ($Action -eq 'status') {
  $configured = $false
  foreach ($config in $configs) {
    $data = Get-VdfText $config
    $apps = Find-VdfBlock -Text $data.text -Key 'apps'
    if ($apps) {
      $app = Find-VdfBlock -Text $data.text -Key $AppId -From ($apps.open + 1) -To $apps.close
      if ($app) { $configured = $configured -or ((Get-LaunchOptions -Text $data.text -AppBlock $app).value -match [regex]::Escape($WrapperMarker)) }
    }
  }
  [pscustomobject]@{ configured = $configured; pending = (Test-Path -LiteralPath $PendingPath); config_files = $configs.Count } | ConvertTo-Json
  exit 0
}
if ($configs.Count -eq 0) { throw 'Steam user configuration was not found. Start Steam once, close it, then rerun the installer.' }

if ($Action -eq 'install') {
  New-Item -ItemType Directory -Force -Path (Split-Path $StatePath) | Out-Null
  $saved = @()
  foreach ($config in $configs) {
    $data = Get-VdfText $config
    $apps = Find-VdfBlock -Text $data.text -Key 'apps'
    $app = if ($apps) { Find-VdfBlock -Text $data.text -Key $AppId -From ($apps.open + 1) -To $apps.close } else { $null }
    $existing = if ($app) { Get-LaunchOptions -Text $data.text -AppBlock $app } else { $null }
    if ($existing -and $existing.value -match [regex]::Escape($WrapperMarker)) { continue }
    $suffix = if ($existing -and -not [string]::IsNullOrWhiteSpace($existing.value)) { ' ' + $existing.value } else { '' }
    $updated = Set-LaunchOptions -Text $data.text -Value ($WrapperCommand + $suffix)
    Write-VdfText -Path $config -Text $updated -Encoding $data.encoding
    $saved += [pscustomobject]@{ config_path = $config; had_original = ($null -ne $existing); original_value = if ($existing) { $existing.value } else { '' } }
  }
  if ($saved.Count -gt 0) { @{ app_id = $AppId; entries = $saved; timestamp = (Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $StatePath }
  Remove-Item -LiteralPath $PendingPath -Force -ErrorAction SilentlyContinue
  [pscustomobject]@{ configured = $true; config_files = $configs.Count } | ConvertTo-Json
  exit 0
}

if (Test-Path -LiteralPath $StatePath) {
  $state = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
  foreach ($entry in @($state.entries)) {
    if (-not (Test-Path -LiteralPath $entry.config_path)) { continue }
    $data = Get-VdfText $entry.config_path
    $updated = Remove-LaunchOptions -Text $data.text -RestoreValue $entry.original_value -HadOriginal ([bool]$entry.had_original)
    if ($updated -ne $data.text) { Write-VdfText -Path $entry.config_path -Text $updated -Encoding $data.encoding }
  }
} else {
  # Recovery path: remove our wrapper when the app folder or saved state is gone.
  foreach ($config in $configs) {
    $data = Get-VdfText $config
    $apps = Find-VdfBlock -Text $data.text -Key 'apps'
    if ($null -eq $apps) { continue }
    $app = Find-VdfBlock -Text $data.text -Key $AppId -From ($apps.open + 1) -To $apps.close
    if ($null -eq $app) { continue }
    $updated = Remove-LaunchOptions -Text $data.text -RestoreValue '' -HadOriginal $false
    if ($updated -ne $data.text) { Write-VdfText -Path $config -Text $updated -Encoding $data.encoding }
  }
}
Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue
