[CmdletBinding()]
param([string]$Bootstrap = 'bootstrap.ps1')
$ErrorActionPreference = 'Stop'
$text = Get-Content -LiteralPath $Bootstrap -Raw
$url = [regex]::Match($text, "https://github.com/[^']+/releases/download/[^']+\.zip").Value
$expected = [regex]::Match($text, "\$ExpectedSha256 = '([A-Fa-f0-9]+)'").Groups[1].Value
if ([string]::IsNullOrWhiteSpace($url) -or [string]::IsNullOrWhiteSpace($expected)) { throw 'Could not extract release URL/hash from bootstrap.ps1.' }
$out = Join-Path $env:TEMP ('rcn-verify-' + [guid]::NewGuid().ToString('N') + '.zip')
Invoke-WebRequest -Uri $url -OutFile $out
$actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $out).Hash
if ($actual -ne $expected) { throw "Release verification failed. Expected $expected, got $actual." }
Write-Host "Verified $url`nSHA-256: $actual"
