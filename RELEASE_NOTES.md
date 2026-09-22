# RCN FPV SkyDive v0.1.72

## Highlights

- Fixed the orange installer banner on Windows PowerShell so it no longer fails before installation.
- Rebuilt the native bridge without local Cargo-cache paths or Windows usernames embedded in it.
- The optional local-source build now downloads a release-pinned, SHA-256-verified source ZIP and checks its built executable for a local username before install.
- Fixed the source-installer package references so its download and verification details always match the published release.
- Fixed the advertised one-line source-installer command so it can run directly from PowerShell.
- Releases now refuse unreviewed untracked files instead of staging everything automatically, and common secret-file patterns are ignored.

## Flight notes

- No controller setup or game binding behavior changed in this release.
- The bridge still starts only with FPV SkyDive and begins with neutral Xbox controls.

## Verification

- PowerShell script parsing and the Windows PowerShell installer-banner regression check passed.
- All 13 Rust unit tests passed.
- A clean remapped Rust release build passed an exact username scan.
- The published binary and source ZIPs will be SHA-256 verified after publication.

## Install or update

```powershell
irm https://github.com/Zouzitou/rcn-fpvskydive/releases/latest/download/bootstrap.ps1 | iex
```
