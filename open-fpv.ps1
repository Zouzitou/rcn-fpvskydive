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
    $path = Join-Path $_ 'steamapps\common\FPV SkyDive'
    if (Test-Path -LiteralPath $path) { (Resolve-Path -LiteralPath $path).Path }
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
Start-Process "steam://rungameid/$AppId"
Write-Host "Opened FPV SkyDive through Steam: $($paths[0])"
