[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Version)
$ErrorActionPreference = 'Stop'
$tag = if ($Version.StartsWith('v')) { $Version } else { "v$Version" }
$stage = Join-Path $env:TEMP ('rcn-release-' + [guid]::NewGuid().ToString('N'))
$payload = Join-Path $stage 'payload'
$zip = Join-Path $stage "rcn-fpvskydive-$tag.zip"
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
$cargo = Get-Content -LiteralPath 'rust-bridge/Cargo.toml' -Raw
$cargo = [regex]::Replace($cargo, '(?m)^version = "[0-9.]+"$', "version = `"$($tag.TrimStart('v'))`"")
Set-Content -LiteralPath 'rust-bridge/Cargo.toml' -Value $cargo -NoNewline
& .\verify-scripts.ps1
cargo test --manifest-path rust-bridge\Cargo.toml
if ($LASTEXITCODE -ne 0) { throw 'Rust tests failed; release cancelled.' }
cargo build --release --manifest-path rust-bridge\Cargo.toml
if ($LASTEXITCODE -ne 0) { throw 'Rust release build failed; release cancelled.' }
$bridge = 'rust-bridge\target\release\rcn-bridge.exe'
$selfTestPassed = $false
for ($attempt = 1; $attempt -le 5; $attempt++) {
  & $bridge self-test
  if ($LASTEXITCODE -eq 0) { $selfTestPassed = $true; break }
  if ($attempt -lt 5) { Start-Sleep -Seconds 1 }
}
if (-not $selfTestPassed) { throw 'Native virtual-controller self-test failed; release cancelled.' }
$readme = Get-Content -LiteralPath 'README.md' -Raw
$readme = [regex]::Replace($readme, 'raw.githubusercontent.com/Zouzitou/rcn-fpvskydive/v[0-9.]+/bootstrap\.ps1', "raw.githubusercontent.com/Zouzitou/rcn-fpvskydive/$tag/bootstrap.ps1")
$readme = [regex]::Replace($readme, 'raw.githubusercontent.com/Zouzitou/rcn-fpvskydive/v[0-9.]+/install-from-source\.ps1', "raw.githubusercontent.com/Zouzitou/rcn-fpvskydive/$tag/install-from-source.ps1")
Set-Content -LiteralPath 'README.md' -Value $readme -NoNewline
$sourceInstaller = Get-Content -LiteralPath 'install-from-source.ps1' -Raw
$sourceInstaller = [regex]::Replace($sourceInstaller, '(?m)^param\(\[string\]\$Ref = ''v[0-9.]+''\)$', "param([string]`$Ref = '$tag')")
Set-Content -LiteralPath 'install-from-source.ps1' -Value $sourceInstaller -NoNewline
New-Item -ItemType Directory -Force -Path (Join-Path $payload 'bin') | Out-Null
Copy-Item -LiteralPath $bridge -Destination (Join-Path $payload 'bin\rcn-bridge.exe') -Force
$items = @('docs','release.ps1','verify-release.ps1','verify-scripts.ps1','verify-installed.ps1','install-app.ps1','install-from-source.ps1','startup.ps1','uninstall.ps1','driver.ps1','open-fpv.ps1','game-check.ps1','launch-fpv.ps1','launch-fpv.cmd','README.md','ARCHITECTURE.md','ACCEPTANCE.md','SECURITY.md','RELEASE_CHECKLIST.md')
foreach ($item in $items) { Copy-Item -LiteralPath $item -Destination $payload -Recurse -Force }
New-DeterministicZip -Source $payload -Destination $zip
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $zip).Hash
$bootstrap = Get-Content -LiteralPath 'bootstrap.ps1' -Raw
$bootstrap = [regex]::Replace($bootstrap, 'releases/download/v[0-9.]+/rcn-fpvskydive-v[0-9.]+\.zip', "releases/download/$tag/rcn-fpvskydive-$tag.zip")
$bootstrap = [regex]::Replace($bootstrap, '(?m)^\$ExpectedSha256 = ''[A-Fa-f0-9]+''$', ('$' + 'ExpectedSha256 = ''' + $hash + ''''))
Set-Content -LiteralPath 'bootstrap.ps1' -Value $bootstrap -NoNewline
Set-Content -LiteralPath (Join-Path $stage 'SHA256SUMS.txt') -Value "$hash  rcn-fpvskydive-$tag.zip"
git add -A
git commit -m "Prepare $tag release"
if ($LASTEXITCODE -ne 0) { throw 'Git commit failed; release cancelled.' }
git push
if ($LASTEXITCODE -ne 0) { throw 'Git push failed; release cancelled.' }
gh release create $tag $zip (Join-Path $stage 'SHA256SUMS.txt') --repo Zouzitou/rcn-fpvskydive --title "RCN FPV SkyDive $tag" --notes "Locally packaged and SHA-256 verified release."
if ($LASTEXITCODE -ne 0) { throw 'GitHub release creation failed.' }
Write-Host "Published $tag with SHA-256 $hash"
