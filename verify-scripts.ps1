[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$files = 'bootstrap.ps1', 'startup.ps1', 'uninstall.ps1', 'driver.ps1', 'launch-fpv.ps1', 'release.ps1', 'verify-release.ps1'
$failed = $false
foreach ($file in $files) {
  $tokens = $null
  $errors = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $file), [ref]$tokens, [ref]$errors)
  if ($errors.Count) {
    $failed = $true
    $errors | ForEach-Object { Write-Error "${file}:$($_.Extent.StartLineNumber): $($_.Message)" }
  } else {
    Write-Host "OK $file"
  }
}
if ($failed) { exit 1 }
