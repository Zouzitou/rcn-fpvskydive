[CmdletBinding()]
param([ValidateSet('diagnose','open')][string]$Action = 'open')
$ErrorActionPreference = 'Stop'
$AppId = '1278060'

function Get-SteamRoots {
  $roots = [System.Collections.Generic.List[string]]::new()
  $keys = 'HKCU:\Software\Valve\Steam','HKLM:\SOFTWARE\WOW6432Node\Valve\Steam','HKLM:\SOFTWARE\Valve\Steam'
  foreach ($key in $keys) {
    $item = Get-ItemProperty $key -ErrorAction SilentlyContinue
    foreach ($value in @($item.SteamPath,$item.InstallPath)) { if ($value) { [void]$roots.Add($value) } }
    if ($item.SteamExe) { [void]$roots.Add((Split-Path $item.SteamExe)) }
  }
  Get-Process steam -ErrorAction SilentlyContinue | ForEach-Object { if ($_.Path) { [void]$roots.Add((Split-Path $_.Path)) } }
  $initial = @($roots | Select-Object -Unique)
  foreach ($root in $initial) {
    $vdf = Join-Path $root 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) {
      $text = Get-Content -LiteralPath $vdf -Raw
      foreach ($match in [regex]::Matches($text,'"path"\s+"([^"]+)"')) {
        $library = $match.Groups[1].Value -replace '\\\\','\'
        [void]$roots.Add($library)
      }
    }
  }
  @($roots | Select-Object -Unique)
}

function Get-FpvPaths {
  @(Get-SteamRoots | ForEach-Object {
    foreach ($folder in 'FPV SkyDive','FPV.SkyDive') {
      $path = Join-Path $_ (Join-Path 'steamapps\common' $folder)
      if (Test-Path -LiteralPath $path) { (Resolve-Path -LiteralPath $path).Path }
    }
  } | Select-Object -Unique)
}

$paths = @(Get-FpvPaths)
if ($Action -eq 'diagnose') {
  [pscustomobject]@{
    app_id = $AppId
    steam_roots = @(Get-SteamRoots)
    installed = ($paths.Count -gt 0)
    install_paths = $paths
  } | ConvertTo-Json -Depth 4
  exit 0
}
if ($paths.Count -eq 0) { throw "FPV SkyDive (Steam app $AppId) was not found in the detected Steam libraries." }
$GameExe = Join-Path $paths[0] 'FPV.SkyDive.exe'
$Root = Join-Path $env:LOCALAPPDATA 'RCN-FPVSkyDive'
$Wrapper = Join-Path $Root 'launch-fpv.ps1'
if (-not (Test-Path -LiteralPath $GameExe)) { throw "FPV SkyDive executable was not found: $GameExe" }
if (-not (Test-Path -LiteralPath $Wrapper)) { throw "Game bridge wrapper was not found: $Wrapper" }
if (Get-Process -Name 'FPV.SkyDive' -ErrorAction SilentlyContinue) {
  throw 'FPV SkyDive is already running. Close it before starting another bridge session.'
}
Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$Wrapper,$GameExe) -WindowStyle Hidden
Write-Host "Starting FPV SkyDive with the RCN bridge: $GameExe"
