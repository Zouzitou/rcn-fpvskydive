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
$init = Get-Content -LiteralPath 'src/rcn_fpv/__init__.py' -Raw
$init = [regex]::Replace($init, '__version__ = "[0-9.]+"', "__version__ = `"$($tag.TrimStart('v'))`"")
Set-Content -LiteralPath 'src/rcn_fpv/__init__.py' -Value $init -NoNewline
$project = Get-Content -LiteralPath 'pyproject.toml' -Raw
$project = [regex]::Replace($project, '(?m)^version = "[0-9.]+"$', "version = `"$($tag.TrimStart('v'))`"")
Set-Content -LiteralPath 'pyproject.toml' -Value $project -NoNewline
py -m pytest -q
$items = @('src','tests','docs','pyproject.toml','requirements.lock','release.ps1','verify-release.ps1','startup.ps1','uninstall.ps1','README.md','ARCHITECTURE.md','ACCEPTANCE.md','SECURITY.md','RELEASE_CHECKLIST.md')
foreach ($item in $items) { Copy-Item -LiteralPath $item -Destination $payload -Recurse -Force }
New-DeterministicZip -Source $payload -Destination $zip
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $zip).Hash
$bootstrap = Get-Content -LiteralPath 'bootstrap.ps1' -Raw
$bootstrap = [regex]::Replace($bootstrap, 'releases/download/v[0-9.]+/rcn-fpvskydive-v[0-9.]+\.zip', "releases/download/$tag/rcn-fpvskydive-$tag.zip")
$bootstrap = [regex]::Replace($bootstrap, '(?m)^\$ExpectedSha256 = ''[A-Fa-f0-9]+''$', ('$' + 'ExpectedSha256 = ''' + $hash + ''''))
Set-Content -LiteralPath 'bootstrap.ps1' -Value $bootstrap -NoNewline
$readme = Get-Content -LiteralPath 'README.md' -Raw
$readme = [regex]::Replace($readme, 'raw.githubusercontent.com/Zouzitou/rcn-fpvskydive/v[0-9.]+/bootstrap\.ps1', "raw.githubusercontent.com/Zouzitou/rcn-fpvskydive/$tag/bootstrap.ps1")
Set-Content -LiteralPath 'README.md' -Value $readme -NoNewline
Set-Content -LiteralPath (Join-Path $stage 'SHA256SUMS.txt') -Value "$hash  rcn-fpvskydive-$tag.zip"
git add -A
git commit -m "Prepare $tag release"
git push
gh release create $tag $zip (Join-Path $stage 'SHA256SUMS.txt') --repo Zouzitou/rcn-fpvskydive --title "RCN FPV SkyDive $tag" --notes "Locally packaged and SHA-256 verified release."
Write-Host "Published $tag with SHA-256 $hash"
