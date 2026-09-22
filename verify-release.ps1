[CmdletBinding()]
param([string]$Bootstrap = 'bootstrap.ps1')
$ErrorActionPreference = 'Stop'
$text = Get-Content -LiteralPath $Bootstrap -Raw
$url = [regex]::Match($text, "https://github.com/[^']+/releases/download/[^']+\.zip").Value
$expected = [regex]::Match($text, '\$ExpectedSha256 = ''([A-Fa-f0-9]+)''').Groups[1].Value
if ([string]::IsNullOrWhiteSpace($url) -or [string]::IsNullOrWhiteSpace($expected)) { throw 'Could not extract release URL/hash from bootstrap.ps1.' }
$out = Join-Path $env:TEMP ('rcn-verify-' + [guid]::NewGuid().ToString('N') + '.zip')
Invoke-WebRequest -Uri $url -OutFile $out
$actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $out).Hash
if ($actual -ne $expected) { throw "Release verification failed. Expected $expected, got $actual." }
Write-Host "Verified $url`nSHA-256: $actual"
$bootstrapDirectory = Split-Path -Parent $Bootstrap
if ([string]::IsNullOrWhiteSpace($bootstrapDirectory)) { $bootstrapDirectory = $PSScriptRoot }
$sourceInstaller = Join-Path $bootstrapDirectory 'install-from-source.ps1'
if (-not (Test-Path -LiteralPath $sourceInstaller -PathType Leaf)) { throw 'install-from-source.ps1 is required to verify the source package.' }
$sourceText = Get-Content -LiteralPath $sourceInstaller -Raw
$sourceUrl = [regex]::Match($sourceText, "https://github.com/[^']+/releases/download/[^']+-source\.zip").Value
$sourceExpected = [regex]::Match($sourceText, '\$ExpectedSourceSha256 = ''([A-Fa-f0-9]{64})''').Groups[1].Value
if ([string]::IsNullOrWhiteSpace($sourceUrl) -or [string]::IsNullOrWhiteSpace($sourceExpected)) { throw 'Could not extract source-package URL/hash from install-from-source.ps1.' }
$sourceOut = Join-Path $env:TEMP ('rcn-verify-source-' + [guid]::NewGuid().ToString('N') + '.zip')
Invoke-WebRequest -Uri $sourceUrl -OutFile $sourceOut
$sourceActual = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceOut).Hash
if ($sourceActual -ne $sourceExpected) { throw "Source-package verification failed. Expected $sourceExpected, got $sourceActual." }
Write-Host "Verified $sourceUrl`nSHA-256: $sourceActual"
