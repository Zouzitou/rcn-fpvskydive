$script:InstallerUseAnsi = $false
try { $script:InstallerUseAnsi = [bool]$Host.UI.SupportsVirtualTerminal } catch { }
$script:InstallerOrange = [char]27 + '[38;5;208m'
$script:InstallerAmber = [char]27 + '[38;5;214m'
$script:InstallerGreen = [char]27 + '[38;5;114m'
$script:InstallerRed = [char]27 + '[38;5;203m'
$script:InstallerDim = [char]27 + '[38;5;245m'
$script:InstallerReset = [char]27 + '[0m'

function Write-InstallerText {
  param([string]$Text, [ValidateSet('Orange', 'Amber', 'Green', 'Red', 'Dim')][string]$Tone = 'Orange')
  $color = Get-Variable -Name ("Installer$Tone") -Scope Script -ValueOnly
  if ($script:InstallerUseAnsi) { Write-Host "$color$Text$script:InstallerReset" }
  else {
    $fallback = if ($Tone -eq 'Green') { 'Green' } elseif ($Tone -eq 'Red') { 'Red' } elseif ($Tone -eq 'Dim') { 'DarkGray' } else { 'DarkYellow' }
    Write-Host $Text -ForegroundColor $fallback
  }
}

function Start-InstallerUi {
  param([string]$Subtitle)
  try { Clear-Host } catch { }
  Write-InstallerText '╔══════════════════════════════════════════════════════╗'
  Write-InstallerText '║                 RCN FPV SKYDIVE                      ║'
  Write-InstallerText '╚══════════════════════════════════════════════════════╝'
  Write-InstallerText "  $Subtitle" 'Dim'
  Write-Host ''
}

function Set-InstallerStep {
  param([int]$Number, [string]$Title, [string]$Detail)
  Write-Progress -Activity 'RCN FPV SkyDive' -Status $Title -PercentComplete ($Number * 20)
  Write-InstallerText ("  [{0}/5]  {1}" -f $Number, $Title)
  if (-not [string]::IsNullOrWhiteSpace($Detail)) { Write-InstallerText ("         {0}" -f $Detail) 'Dim' }
}

function Complete-InstallerUi {
  param([string]$Message)
  Write-Progress -Activity 'RCN FPV SkyDive' -Completed
  Write-Host ''
  Write-InstallerText '  ✓  INSTALLATION COMPLETE' 'Green'
  Write-InstallerText ("     {0}" -f $Message) 'Dim'
}

function Fail-InstallerUi {
  param([string]$Message)
  Write-Progress -Activity 'RCN FPV SkyDive' -Completed
  Write-Host ''
  Write-InstallerText '  !  INSTALLATION STOPPED SAFELY' 'Red'
  Write-InstallerText ("     {0}" -f $Message) 'Dim'
}
