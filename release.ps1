[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Version,
  [string]$NotesFile = 'RELEASE_NOTES.md'
)
$ErrorActionPreference = 'Stop'
$tag = if ($Version.StartsWith('v')) { $Version } else { "v$Version" }
$NotesPath = Join-Path $PSScriptRoot $NotesFile
if (-not (Test-Path -LiteralPath $NotesPath -PathType Leaf)) { throw "Release notes are required. Copy RELEASE_NOTES_TEMPLATE.md to $NotesFile and complete it before publishing." }
$ReleaseNotes = Get-Content -LiteralPath $NotesPath -Raw
if ([string]::IsNullOrWhiteSpace($ReleaseNotes)) { throw 'Release notes are empty; release cancelled.' }
if ($ReleaseNotes -match '<[^>]+>' -or $ReleaseNotes -match '\[Describe|\[State|\[List') { throw 'Release notes still contain template placeholders; release cancelled.' }
if ($ReleaseNotes -notmatch [regex]::Escape("# RCN FPV SkyDive $tag")) { throw "Release notes must start with '# RCN FPV SkyDive $tag'; release cancelled." }
foreach ($heading in '## Highlights', '## Flight notes', '## Verification', '## Install or update') {
  if ($ReleaseNotes -notmatch [regex]::Escape($heading)) { throw "Release notes are missing '$heading'; release cancelled." }
}
$stage = Join-Path $env:TEMP ('rcn-release-' + [guid]::NewGuid().ToString('N'))
$payload = Join-Path $stage 'payload'
$sourcePayload = Join-Path $stage 'source-payload'
$zip = Join-Path $stage "rcn-fpvskydive-$tag.zip"
$sourceZip = Join-Path $stage "rcn-fpvskydive-$tag-source.zip"
New-Item -ItemType Directory -Force -Path $payload | Out-Null
function New-DeterministicZip {
  param([string]$Source, [string]$Destination)
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $stream = [System.IO.File]::Open($Destination, [System.IO.FileMode]::Create)
  $archive = [System.IO.Compression.ZipArchive]::new($stream, [System.IO.Compression.ZipArchiveMode]::Create, $false)
  try {
    Get-ChildItem -LiteralPath $Source -Recurse -File | Sort-Object FullName | ForEach-Object {
      $relative = $_.FullName.Substring($Source.Length).TrimStart('\', '/') -replace '\\', '/'
      $entry = $archive.CreateEntry($relative, [System.IO.Compression.CompressionLevel]::Optimal)
      $entry.LastWriteTime = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
      $input = [System.IO.File]::OpenRead($_.FullName)
      $output = $entry.Open()
      try { $input.CopyTo($output) } finally { $output.Dispose(); $input.Dispose() }
    }
  } finally { $archive.Dispose(); $stream.Dispose() }
}
function Enable-PrivateCargoPaths {
  $previous = $env:CARGO_ENCODED_RUSTFLAGS
  $remap = "--remap-path-prefix=$env:USERPROFILE=<USERPROFILE>"
  $env:CARGO_ENCODED_RUSTFLAGS = if ([string]::IsNullOrEmpty($previous)) { $remap } else { $previous + [char]0x1f + $remap }
  return $previous
}
function Restore-CargoPaths {
  param([AllowEmptyString()][string]$Previous)
  if ($null -eq $Previous) { Remove-Item Env:CARGO_ENCODED_RUSTFLAGS -ErrorAction SilentlyContinue }
  else { $env:CARGO_ENCODED_RUSTFLAGS = $Previous }
}
function Assert-PrivateArtifact {
  param([Parameter(Mandatory = $true)][string]$Path)
  $patterns = @($env:USERNAME) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  foreach ($pattern in $patterns) {
    & rg -a -i -q --fixed-strings -- $pattern $Path
    if ($LASTEXITCODE -eq 0) { throw "Release artifact contains the private build identity '$pattern'; release cancelled." }
    if ($LASTEXITCODE -gt 1) { throw 'Could not inspect a release artifact for private build identities; release cancelled.' }
  }
}
function Assert-PrivatePackage {
  param([Parameter(Mandatory = $true)][string]$Path)
  $inspection = Join-Path $stage ('privacy-inspection-' + [guid]::NewGuid().ToString('N'))
  try {
    Expand-Archive -LiteralPath $Path -DestinationPath $inspection -Force
    foreach ($file in Get-ChildItem -LiteralPath $inspection -Recurse -File) {
      Assert-PrivateArtifact -Path $file.FullName
    }
  } finally {
    if (Test-Path -LiteralPath $inspection) { Remove-Item -LiteralPath $inspection -Recurse -Force }
  }
}
function Copy-TrackedSource {
  param([Parameter(Mandatory = $true)][string]$Destination)
  foreach ($relative in (& git ls-files)) {
    if ($relative -eq 'install-from-source.ps1') { continue }
    $source = Join-Path $PSScriptRoot $relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
    $target = Join-Path $Destination $relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    Copy-Item -LiteralPath $source -Destination $target -Force
  }
}
if ((git config user.name) -ne 'Zouzitou' -or (git config user.email) -ne '204303365+Zouzitou@users.noreply.github.com') { throw 'Git identity must be Zouzitou <204303365+Zouzitou@users.noreply.github.com>; release cancelled.' }
if ((& git diff --cached --name-only)) { throw 'Release cancelled because staged changes must be reviewed before running release.ps1.' }
if ((& git ls-files --others --exclude-standard)) { throw 'Release cancelled because untracked files must be reviewed and committed before running release.ps1.' }
$cargo = Get-Content -LiteralPath 'rust-bridge/Cargo.toml' -Raw
$cargo = [regex]::Replace($cargo, '(?m)^version = "[0-9.]+"$', "version = `"$($tag.TrimStart('v'))`"")
Set-Content -LiteralPath 'rust-bridge/Cargo.toml' -Value $cargo -NoNewline
& .\verify-scripts.ps1
$readme = Get-Content -LiteralPath 'README.md' -Raw
$readme = [regex]::Replace($readme, 'raw.githubusercontent.com/Zouzitou/rcn-fpvskydive/v[0-9.]+/bootstrap\.ps1', "raw.githubusercontent.com/Zouzitou/rcn-fpvskydive/$tag/bootstrap.ps1")
$readme = [regex]::Replace($readme, 'raw.githubusercontent.com/Zouzitou/rcn-fpvskydive/v[0-9.]+/install-from-source\.ps1', "raw.githubusercontent.com/Zouzitou/rcn-fpvskydive/$tag/install-from-source.ps1")
Set-Content -LiteralPath 'README.md' -Value $readme -NoNewline
$PreviousCargoPaths = Enable-PrivateCargoPaths
try {
  cargo clean --manifest-path rust-bridge\Cargo.toml
  cargo generate-lockfile --offline --manifest-path rust-bridge\Cargo.toml
  if ($LASTEXITCODE -ne 0) { throw 'Rust lockfile update failed; release cancelled.' }
  cargo test --locked --manifest-path rust-bridge\Cargo.toml
  if ($LASTEXITCODE -ne 0) { throw 'Rust tests failed; release cancelled.' }
  cargo build --locked --release --manifest-path rust-bridge\Cargo.toml
  if ($LASTEXITCODE -ne 0) { throw 'Rust release build failed; release cancelled.' }
} finally { Restore-CargoPaths -Previous $PreviousCargoPaths }
$bridge = 'rust-bridge\target\release\rcn-bridge.exe'
Assert-PrivateArtifact -Path $bridge
$selfTestPassed = $false
for ($attempt = 1; $attempt -le 5; $attempt++) {
  & $bridge self-test
  if ($LASTEXITCODE -eq 0) { $selfTestPassed = $true; break }
  if ($attempt -lt 5) { Start-Sleep -Seconds 1 }
}
if (-not $selfTestPassed) { throw 'Native virtual-controller self-test failed; release cancelled.' }
$sourceInstaller = Get-Content -LiteralPath 'install-from-source.ps1' -Raw
$sourceInstaller = [regex]::Replace($sourceInstaller, '(?m)^param\(\[string\]\$Ref = ''v[0-9.]+''\)$', "param([string]`$Ref = '$tag')")
Set-Content -LiteralPath 'install-from-source.ps1' -Value $sourceInstaller -NoNewline
New-Item -ItemType Directory -Force -Path $sourcePayload | Out-Null
Copy-TrackedSource -Destination $sourcePayload
New-DeterministicZip -Source $sourcePayload -Destination $sourceZip
$sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceZip).Hash
$sourceInstaller = Get-Content -LiteralPath 'install-from-source.ps1' -Raw
$sourceInstaller = [regex]::Replace($sourceInstaller, "releases/download/v[0-9.]+/rcn-fpvskydive-v[0-9.]+-source\\.zip", "releases/download/$tag/rcn-fpvskydive-$tag-source.zip")
$sourceInstaller = [regex]::Replace($sourceInstaller, "(?m)^\$ExpectedSourceSha256 = '[^']+'$", ('$' + "ExpectedSourceSha256 = '$sourceHash'"))
Set-Content -LiteralPath 'install-from-source.ps1' -Value $sourceInstaller -NoNewline
New-Item -ItemType Directory -Force -Path (Join-Path $payload 'bin') | Out-Null
Copy-Item -LiteralPath $bridge -Destination (Join-Path $payload 'bin\rcn-bridge.exe') -Force
$items = @('docs','AGENTS.md','CLAUDE.md','GEMINI.md','bootstrap.ps1','release.ps1','verify-release.ps1','verify-scripts.ps1','verify-installed.ps1','installer-ui.ps1','install-app.ps1','install-from-source.ps1','startup.ps1','uninstall.ps1','driver.ps1','open-fpv.ps1','game-check.ps1','launch-fpv.ps1','launch-fpv.cmd','steam-launch-options.ps1','LICENSE','README.md','ARCHITECTURE.md','ACCEPTANCE.md','SECURITY.md','RELEASE_CHECKLIST.md','RELEASE_NOTES_TEMPLATE.md')
foreach ($item in $items) { Copy-Item -LiteralPath $item -Destination $payload -Recurse -Force }
New-DeterministicZip -Source $payload -Destination $zip
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $zip).Hash
Assert-PrivatePackage -Path $sourceZip
Assert-PrivatePackage -Path $zip
$bootstrap = Get-Content -LiteralPath 'bootstrap.ps1' -Raw
$bootstrap = [regex]::Replace($bootstrap, 'releases/download/v[0-9.]+/rcn-fpvskydive-v[0-9.]+\.zip', "releases/download/$tag/rcn-fpvskydive-$tag.zip")
$bootstrap = [regex]::Replace($bootstrap, '(?m)^\$ExpectedSha256 = ''[A-Fa-f0-9]+''$', ('$' + 'ExpectedSha256 = ''' + $hash + ''''))
Set-Content -LiteralPath 'bootstrap.ps1' -Value $bootstrap -NoNewline
Set-Content -LiteralPath (Join-Path $stage 'SHA256SUMS.txt') -Value @("$hash  rcn-fpvskydive-$tag.zip", "$sourceHash  rcn-fpvskydive-$tag-source.zip")
git add --update
git commit -m "Prepare $tag release"
if ($LASTEXITCODE -ne 0) { throw 'Git commit failed; release cancelled.' }
git push
if ($LASTEXITCODE -ne 0) { throw 'Git push failed; release cancelled.' }
gh release create $tag $zip $sourceZip (Join-Path $stage 'SHA256SUMS.txt') 'bootstrap.ps1' 'install-from-source.ps1' --repo Zouzitou/rcn-fpvskydive --title "RCN FPV SkyDive $tag" --notes-file $NotesPath
if ($LASTEXITCODE -ne 0) { throw 'GitHub release creation failed.' }
Write-Host "Published $tag with SHA-256 $hash"
