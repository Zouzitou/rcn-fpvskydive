[CmdletBinding()]
param(
  [ValidateSet('diagnose','validate','install')][string]$Action = 'diagnose',
  [string]$InfPath
)
$ErrorActionPreference = 'Stop'

function Get-ProtocolInterfaces {
  @(Get-CimInstance Win32_PnPEntity | Where-Object {
    $_.Status -eq 'OK' -and $_.PNPDeviceID -match 'VID_2CA3' -and $_.Name -match 'For Protocol.*\(COM[0-9]+\)'
  } | Select-Object Status,Name,PNPDeviceID)
}

function Test-Administrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-InfVersionSection {
  param([Parameter(Mandatory=$true)][string]$InfText)
  $match = [regex]::Match($InfText, '(?ims)^\s*\[Version\]\s*(.*?)(?=^\s*\[|\z)')
  if (-not $match.Success) { throw 'The driver INF has no [Version] section.' }
  return $match.Groups[1].Value
}

function Get-DriverCatalogs {
  param([Parameter(Mandatory=$true)][string]$VersionSection)
  $catalogs = @(
    [regex]::Matches($VersionSection, '(?im)^\s*CatalogFile(?:\.[A-Za-z0-9_]+)?\s*=\s*"?([^"\r\n]+?)"?\s*$') |
      ForEach-Object { $_.Groups[1].Value.Trim() } |
      Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
      Select-Object -Unique
  )
  if ($catalogs.Count -eq 0) { throw 'The driver INF does not reference a package catalog and was rejected.' }
  return $catalogs
}

function Test-DjiProvider {
  param(
    [Parameter(Mandatory=$true)][string]$VersionSection,
    [Parameter(Mandatory=$true)][string]$InfText
  )
  $provider = [regex]::Match($VersionSection, '(?im)^\s*Provider\s*=\s*(.+?)\s*$')
  if (-not $provider.Success) { return $false }
  $providerValue = $provider.Groups[1].Value.Trim().Trim('"')
  if ($providerValue -match '(?i)DJI|Da-Jiang') { return $true }
  $token = [regex]::Match($providerValue, '^%(.+)%$')
  if (-not $token.Success) { return $false }
  $tokenName = [regex]::Escape($token.Groups[1].Value)
  $definitionPattern = '(?im)^\s*{0}\s*=\s*"([^"]*)"' -f $tokenName
  $definition = [regex]::Match($InfText, $definitionPattern)
  return $definition.Success -and $definition.Groups[1].Value -match '(?i)DJI|Da-Jiang'
}

function Test-DjiDriverPackage {
  param([Parameter(Mandatory=$true)][string]$InfPath)
  $infText = Get-Content -LiteralPath $InfPath -Raw
  $versionSection = Get-InfVersionSection -InfText $infText
  if (-not (Test-DjiProvider -VersionSection $versionSection -InfText $infText)) {
    throw 'The driver INF does not declare DJI as its provider and was rejected.'
  }
  if ($infText -notmatch '(?i)VID[_&]2CA3') {
    throw 'The INF does not declare DJI VID_2CA3 and was rejected.'
  }

  $packageDirectory = [IO.Path]::GetDirectoryName($InfPath)
  foreach ($catalogName in (Get-DriverCatalogs -VersionSection $versionSection)) {
    if ([IO.Path]::GetFileName($catalogName) -ne $catalogName) {
      throw 'The driver INF contains an unsafe catalog path and was rejected.'
    }
    $catalogPath = Join-Path $packageDirectory $catalogName
    if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
      throw "The driver package is incomplete: referenced catalog '$catalogName' is missing."
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $catalogPath
    if ($signature.Status -ne 'Valid') {
      throw "The driver catalog '$catalogName' signature is not valid: $($signature.Status)."
    }
    $subject = [string]$signature.SignerCertificate.Subject
    if ($subject -notmatch '(?i)DJI|Da-Jiang|Microsoft Windows Hardware Compatibility Publisher|Microsoft Corporation') {
      throw "The driver catalog '$catalogName' is not signed by DJI or a trusted Microsoft hardware publisher and was rejected."
    }
  }
}

if ($Action -eq 'diagnose') {
  $interfaces = Get-ProtocolInterfaces
  if ($interfaces.Count -eq 0) {
    [pscustomobject]@{ state='missing_protocol_interface'; detail='No healthy DJI Protocol COM interface was found'; interfaces=@() } | ConvertTo-Json -Depth 4
  } else {
    [pscustomobject]@{ state='protocol_interface_present'; detail='A healthy DJI Protocol COM interface is present'; interfaces=$interfaces } | ConvertTo-Json -Depth 4
  }
  exit 0
}

if ([string]::IsNullOrWhiteSpace($InfPath)) { throw 'Install requires -InfPath pointing to the official DJI VCOM INF.' }
$resolved = (Resolve-Path -LiteralPath $InfPath -ErrorAction Stop).Path
if ([IO.Path]::GetExtension($resolved) -ne '.inf') { throw 'The driver package path must end in .inf.' }
Test-DjiDriverPackage -InfPath $resolved
if ($Action -eq 'validate') {
  [pscustomobject]@{ state='package_validated'; inf=(Split-Path -Leaf $resolved) } | ConvertTo-Json -Compress
  exit 0
}
if (-not (Test-Administrator)) {
  Write-Host 'Driver-store installation requires administrator approval. Windows will show a UAC prompt.'
  $argumentList = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$PSCommandPath,'-Action','install','-InfPath',$resolved)
  $elevated = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argumentList -Wait -PassThru
  exit $elevated.ExitCode
}

Write-Host "Installing verified DJI VCOM package: $resolved"
& pnputil.exe /add-driver $resolved /install
if ($LASTEXITCODE -ne 0) { throw "pnputil failed with exit code $LASTEXITCODE." }
& pnputil.exe /scan-devices | Out-Host
Start-Sleep -Seconds 2
$interfaces = Get-ProtocolInterfaces
if ($interfaces.Count -eq 0) { throw 'Driver installation completed but no healthy DJI Protocol interface appeared after rescan.' }
[pscustomobject]@{ state='installed_and_validated'; inf=$resolved; interfaces=$interfaces } | ConvertTo-Json -Depth 4
