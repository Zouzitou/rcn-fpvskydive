[CmdletBinding()]
param(
  [ValidateSet('diagnose','install')][string]$Action = 'diagnose',
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
$signature = Get-AuthenticodeSignature -LiteralPath $resolved
if ($signature.Status -ne 'Valid') { throw "Driver INF signature is not valid: $($signature.Status)." }
$infText = Get-Content -LiteralPath $resolved -Raw
if ($infText -notmatch '(?i)VID[_&]2CA3') { throw 'The INF does not declare DJI VID_2CA3 and was rejected.' }
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
