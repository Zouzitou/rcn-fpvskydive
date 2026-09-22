[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$files = 'bootstrap.ps1', 'installer-ui.ps1', 'install-app.ps1', 'install-from-source.ps1', 'startup.ps1', 'uninstall.ps1', 'driver.ps1', 'open-fpv.ps1', 'game-check.ps1', 'launch-fpv.ps1', 'steam-launch-options.ps1', 'verify-installed.ps1', 'release.ps1', 'verify-release.ps1'
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

# Exercise the installer banner in Windows PowerShell itself. A UTF-8
# box-drawing character can decode to a curly apostrophe in PowerShell 5.1,
# turning part of the title into a positional parameter.
$uiPath = Join-Path $PSScriptRoot 'installer-ui.ps1'
$uiOutput = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "& { . '$uiPath'; Start-InstallerUi -Subtitle 'Installer self-check' }" 2>&1
if ($LASTEXITCODE -ne 0 -or ($uiOutput -join "`n") -match 'Cannot validate argument on parameter') {
  Write-Error 'installer-ui.ps1 banner failed under Windows PowerShell.'
  exit 1
}
Write-Host 'OK installer banner compatibility'

# Steam validates the first executable in a %command% wrapper before launch.
# A bare cmd.exe can be rejected as AppError_28 even though Windows would find it.
$steamSetup = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'steam-launch-options.ps1') -Raw
if ($steamSetup -match "(?m)^\$WrapperCommand\s*=\s*'cmd\.exe" -or
    $steamSetup -notmatch [regex]::Escape('$CommandProcessor') -or
    $steamSetup -notmatch [regex]::Escape('$existing.value -ne $WrapperCommand')) {
  Write-Error 'steam-launch-options.ps1 does not enforce and repair an absolute command-processor path.'
  exit 1
}
Write-Host 'OK Steam launch-wrapper executable gate'

# The driver package validator must fail before elevation or pnputil when an
# apparently DJI-shaped package is incomplete. This fixture uses a Provider
# token deliberately, covering normal INF string indirection as well.
$fixture = Join-Path $PSScriptRoot 'tests\driver\missing-catalog.inf'
$driverOutput = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'driver.ps1') -Action validate -InfPath $fixture 2>&1
if ($LASTEXITCODE -eq 0 -or ($driverOutput -join "`n") -notmatch 'referenced catalog.*missing') {
  Write-Error 'driver.ps1 accepted or misclassified a package with a missing catalog.'
  exit 1
}
Write-Host 'OK driver package rejection gate'
