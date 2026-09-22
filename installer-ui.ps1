$script:InstallerUseAnsi = $false
try { $script:InstallerUseAnsi = [bool]$Host.UI.SupportsVirtualTerminal } catch { }
$script:InstallerOrange = [char]27 + '[38;5;208m'
$script:InstallerAmber = [char]27 + '[38;5;214m'
$script:InstallerGreen = [char]27 + '[38;5;114m'
$script:InstallerRed = [char]27 + '[38;5;203m'
$script:InstallerDim = [char]27 + '[38;5;245m'
$script:InstallerReset = [char]27 + '[0m'

function Write-InstallerText {
  param(
    [Parameter(Mandatory = $true, Position = 0)][AllowEmptyString()][string]$Text,
    [Parameter(Position = 1)][ValidateSet('Orange', 'Amber', 'Green', 'Red', 'Dim')][string]$Tone = 'Orange'
  )
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
  # Keep this banner ASCII. Windows PowerShell 5.1 reads a UTF-8 script without
  # a BOM as the active ANSI code page; box-drawing bytes can become a curly
  # apostrophe and break PowerShell's quoted-string parsing.
  Write-InstallerText -Text '+------------------------------------------------------+'
  Write-InstallerText -Text '|                 RCN FPV SKYDIVE                      |'
  Write-InstallerText -Text '+------------------------------------------------------+'
  Write-InstallerText -Text ("  {0}" -f $Subtitle) -Tone 'Dim'
  Write-Host ''
}

function Set-InstallerStep {
  param([int]$Number, [string]$Title, [string]$Detail)
  Write-Progress -Activity 'RCN FPV SkyDive' -Status $Title -PercentComplete ($Number * 20)
  Write-InstallerText -Text ("  [{0}/5]  {1}" -f $Number, $Title)
  if (-not [string]::IsNullOrWhiteSpace($Detail)) { Write-InstallerText -Text ("         {0}" -f $Detail) -Tone 'Dim' }
}

function Complete-InstallerUi {
  param([string]$Message)
  Write-Progress -Activity 'RCN FPV SkyDive' -Completed
  Write-Host ''
  Write-InstallerText -Text '  [OK] INSTALLATION COMPLETE' -Tone 'Green'
  Write-InstallerText -Text ("     {0}" -f $Message) -Tone 'Dim'
}

function Fail-InstallerUi {
  param([string]$Message)
  Write-Progress -Activity 'RCN FPV SkyDive' -Completed
  Write-Host ''
  Write-InstallerText -Text '  [!] INSTALLATION STOPPED SAFELY' -Tone 'Red'
  Write-InstallerText -Text ("     {0}" -f $Message) -Tone 'Dim'
}
